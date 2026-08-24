import 'package:uuid/uuid.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';

/// A minimal descriptor of a chat to send into, decoupled from ChatScreen so a
/// share can be delivered without opening the conversation UI.
class ShareTarget {
  /// One of: trip | dm | group | table.
  final String chatType;

  /// The conversation's id (chat_id for trip/dm, group_id for group, table_id
  /// otherwise).
  final String tableId;

  /// The Ably channel for live delivery.
  final String channelId;

  /// For a nicer confirmation ("Shared to Alex, …").
  final String title;

  const ShareTarget({
    required this.chatType,
    required this.tableId,
    required this.channelId,
    required this.title,
  });
}

/// Headlessly delivers a [SharePayload] into one or more chats WITHOUT opening
/// ChatScreen — the multi-select share path.
///
/// Mirrors ChatScreen._persistAndPublish: inserts a `content_type: 'share'`
/// message into the correct table per chat type (which fires the
/// handle_new_message() trigger → notifications/push server-side) and then
/// publishes to Ably for live delivery. Each message gets a stable UUID, so a
/// Telegram-mode chat's cloud sync and the Ably echo dedup on the sender's side
/// when they next open the conversation — no double message.
class ShareSender {
  ShareSender._();

  static final AblyService _ably = AblyService();

  /// Sends [payload] to every target as a `share` card. Returns how many
  /// succeeded / failed.
  static Future<({int sent, int failed})> send(
    List<ShareTarget> targets,
    SharePayload payload,
  ) {
    return _fanOut(targets, payload.toMessageContent(), 'share');
  }

  /// Forwards an existing message's raw [content] + [contentType] (text, image,
  /// gif, share, …) to every target — same headless delivery as [send], but
  /// flagged so recipients see a "Forwarded" tag.
  static Future<({int sent, int failed})> forward(
    List<ShareTarget> targets, {
    required String content,
    required String contentType,
  }) {
    return _fanOut(targets, content, contentType, forwarded: true);
  }

  /// Inserts [content] (of [contentType]) into each target's backing table and
  /// publishes to Ably — the shared headless path for share + forward.
  static Future<({int sent, int failed})> _fanOut(
    List<ShareTarget> targets,
    String content,
    String contentType, {
    bool forwarded = false,
  }) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null || targets.isEmpty || content.isEmpty) {
      return (sent: 0, failed: targets.length);
    }

    // Fetch the sender's identity once for the Ably echo (the DB trigger derives
    // sender_name itself, so the insert doesn't need it).
    String senderName = 'Someone';
    String? senderPhoto;
    try {
      final u = await SupabaseConfig.client
          .from('users')
          .select('display_name')
          .eq('id', userId)
          .single();
      senderName = (u['display_name'] as String?) ?? 'Someone';
      final p = await SupabaseConfig.client
          .from('user_photos')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .maybeSingle();
      senderPhoto = p?['photo_url'] as String?;
    } catch (_) {
      // Non-fatal: fall back to defaults for the live echo.
    }

    var sent = 0;
    var failed = 0;
    for (final t in targets) {
      final ok = await _sendOne(
          t, content, contentType, forwarded, userId, senderName, senderPhoto);
      if (ok) {
        sent++;
      } else {
        failed++;
      }
    }
    return (sent: sent, failed: failed);
  }

  static Future<bool> _sendOne(
    ShareTarget t,
    String content,
    String contentType,
    bool forwarded,
    String userId,
    String senderName,
    String? senderPhoto,
  ) async {
    final messageId = const Uuid().v4();
    try {
      switch (t.chatType) {
        case 'trip':
          await SupabaseConfig.client.from('trip_messages').insert({
            'id': messageId,
            'chat_id': t.tableId,
            'sender_id': userId,
            'content': content,
            'message_type': contentType,
            'is_forwarded': forwarded,
          });
          break;
        case 'dm':
          await SupabaseConfig.client.from('direct_messages').insert({
            'id': messageId,
            'chat_id': t.tableId,
            'sender_id': userId,
            'content': content,
            'message_type': contentType,
            'is_forwarded': forwarded,
          });
          break;
        case 'group':
          await SupabaseConfig.client.from('messages').insert({
            'id': messageId,
            'group_id': t.tableId,
            'sender_id': userId,
            'content': content,
            'content_type': contentType,
            'is_forwarded': forwarded,
          });
          break;
        default:
          await SupabaseConfig.client.from('messages').insert({
            'id': messageId,
            'table_id': t.tableId,
            'sender_id': userId,
            'content': content,
            'content_type': contentType,
            'is_forwarded': forwarded,
          });
      }

      await _ably.publishMessage(
        channelName: t.channelId,
        content: content,
        contentType: contentType,
        senderId: userId,
        senderName: senderName,
        senderPhotoUrl: senderPhoto,
        messageId: messageId,
        isForwarded: forwarded,
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
