import 'dart:async';
import 'dart:io';

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/features/support/models/support_models.dart';

/// Data access for the async support system.
///
/// Contract, agreed in team_comms #305–#317:
///   - web's `support_messages` is the ONLY copy of message text; we read and
///     write it directly under RLS and never mirror bodies into our own tables
///   - the `chat_inbox` row is a pointer, maintained server-side by web's
///     trigger calling our `upsert_support_inbox` — the app never writes it
///   - Ably carries a SIGNAL, never content: `{ "ticketId": "<uuid>" }` and
///     nothing renderable. On receipt we refetch from Postgres. This is what
///     makes the bundled publish key harmless here: the worst a forged publish
///     can do is make a client refetch rows it is already allowed to read.
class SupportService {
  static final SupportService _instance = SupportService._internal();
  factory SupportService() => _instance;
  SupportService._internal();

  final _client = SupabaseConfig.client;
  final _ably = AblyService();

  /// Channels are scoped by Supabase project ref rather than by build flavour
  /// (#284, reaffirmed for support in #306): a thread's reality is decided by
  /// the database it lives in, so a debug client pointed at prod is looking at
  /// real prod threads and belongs on the same channel.
  ///
  /// Not a secret — it is the public project identifier, and the same value is
  /// already visible in storage URLs the app renders.
  static const String _projectRef = 'rahhezqtkpvkialnduft';

  static String ticketChannel(String ticketId) =>
      'hh:$_projectRef:support:$ticketId';

  /// Web's agent console watches this so a brand-new thread appears without a
  /// poll. They deleted their 60s poll on the strength of us publishing here
  /// (#316), so every path that creates a ticket or adds a requester message
  /// must ring it.
  static String get queueChannel => 'hh:$_projectRef:support:queue';

  // ── Reads ────────────────────────────────────────────────────────────────

  /// The signed-in user's support threads, newest activity first.
  ///
  /// The `user_id` filter is NOT redundant with RLS. The SELECT policy on
  /// support_tickets reads
  ///
  ///     user_id = auth.uid() OR is_partner_owner(partner_id) OR is_support_agent()
  ///
  /// so for the five admin accounts it admits EVERY ticket on the platform.
  /// Leaning on RLS for "mine" showed an admin a stranger's support thread in
  /// their own inbox, and then failed at the reply because
  /// can_reply_support_ticket() has no agent branch. Scope it here, explicitly.
  Future<List<SupportTicket>> myTickets() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _client
        .from('support_tickets')
        .select('id, reference, subject, status, category, last_message_at, created_at')
        .eq('ticket_type', 'support')
        .eq('user_id', uid)
        .order('last_message_at', ascending: false);
    return (rows as List)
        .map((r) => SupportTicket.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// The most recent thread that is still ACTIVE (open or pending), or null.
  ///
  /// Used to decide whether "Contact support" resumes a conversation or starts
  /// one. Resolved threads are excluded on purpose, not just closed ones: a
  /// finished conversation ends, and the next contact is a new ticket
  /// (see SupportTicket.isFinished).
  Future<SupportTicket?> latestOpenTicket() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    // See myTickets(): user_id is scoped here, not left to RLS.
    final rows = await _client
        .from('support_tickets')
        .select('id, reference, subject, status, category, last_message_at, created_at')
        .eq('ticket_type', 'support')
        .eq('user_id', uid)
        .inFilter('status', ['open', 'pending'])
        .order('last_message_at', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return SupportTicket.fromJson(Map<String, dynamic>.from(list.first));
  }

  /// Also scoped to the caller: this screen is reachable from a push payload,
  /// and an agent account would otherwise be able to open any ticket id in the
  /// ordinary user-facing support view.
  Future<SupportTicket?> getTicket(String ticketId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('support_tickets')
        .select('id, reference, subject, status, category, last_message_at, created_at')
        .eq('id', ticketId)
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return SupportTicket.fromJson(Map<String, dynamic>.from(row));
  }

  /// Every message on a thread, oldest first.
  ///
  /// Ordered by `seq`, not `created_at` — web added the sequence for exactly
  /// this reason (#309/#316). `internal` is filtered here too even though RLS
  /// already excludes staff notes, so a future policy slip cannot turn into a
  /// leak in the reader.
  Future<List<SupportMessage>> fetchThread(String ticketId) async {
    final rows = await _client
        .from('support_messages')
        .select(
          'id, ticket_id, sender, body, internal, seq, created_at, deleted_at, '
          'sender_user_id, '
          'support_attachments(id, message_id, storage_path, file_name, mime_type, size_bytes)',
        )
        .eq('ticket_id', ticketId)
        .order('seq', ascending: true);
    return (rows as List)
        .map((r) => SupportMessage.fromJson(Map<String, dynamic>.from(r)))
        .where((m) => !m.internal)
        .toList();
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  /// Opens a thread and posts its first message atomically.
  ///
  /// Goes through our own `open_support_ticket_app` rather than web's
  /// `open_support_ticket`, which hardcodes `source = 'organizer_web'` and
  /// would file every app ticket as a web organizer one.
  ///
  /// [subject] should be derived from context where we have any — an agent
  /// scanning the queue gets far more from "Ticket issue – Launch Party" than
  /// from the first sentence of a paragraph. Null falls back to the first 80
  /// characters of [body], matching web's own synthesis.
  Future<SupportTicket> openTicket({
    required String body,
    required SupportCategory category,
    String? subject,
    String? openedFromPath,
  }) async {
    final rows = await _client.rpc(
      'open_support_ticket_app',
      params: {
        'p_body': body.trim(),
        'p_category': category.value,
        'p_subject': subject,
        'p_opened_from_path': openedFromPath,
      },
    );

    final list = (rows as List);
    if (list.isEmpty) {
      throw StateError('open_support_ticket_app returned no row');
    }
    final id = list.first['id'].toString();

    // A new thread is not in the agent console's watch list yet, so the
    // per-ticket channel would reach nobody. Ring the queue.
    await _publish(queueChannel, id);
    await _publish(ticketChannel(id), id);

    final ticket = await getTicket(id);
    if (ticket == null) throw StateError('Ticket $id not readable after open');
    return ticket;
  }

  /// Posts a reply as the requester.
  ///
  /// RLS enforces sender='requester' and refuses a closed thread, so callers
  /// must gate on [SupportTicket.isClosed] BEFORE letting the user type — the
  /// rejection carries no usable reason.
  Future<void> sendMessage({
    required String ticketId,
    required String body,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    await _client.from('support_messages').insert({
      'ticket_id': ticketId,
      'sender': 'requester',
      'sender_user_id': uid,
      'body': body.trim(),
      'internal': false,
    });

    // Requester messages ring the queue too, not just the thread: a reply to a
    // RESOLVED thread reopens it, and the console was never subscribed to a
    // thread it had closed out of its list (#316).
    await _publish(ticketChannel(ticketId), ticketId);
    await _publish(queueChannel, ticketId);
  }

  /// Retracts one of the requester's own messages.
  ///
  /// The body is destroyed in Postgres, not flagged, and web re-mirrors the
  /// inbox preview so a retracted secret does not survive as a subtitle. Agents
  /// cannot retract, by design — a support thread is the record a user points
  /// at later.
  Future<void> retractMessage({
    required String messageId,
    required String ticketId,
  }) async {
    // Returns the storage paths of any files that were on the message. The RPC
    // deletes the support_attachments ROWS but cannot reach the objects, so
    // purging them is the CALLER's job — skip this and a retracted screenshot
    // of someone's bank details survives in the bucket, which is the entire
    // failure mode the feature exists to prevent.
    final result = await _client.rpc(
      'retract_support_message',
      params: {'p_message_id': messageId},
    );

    final paths = (result as List?)?.map((e) => e.toString()).toList() ?? [];
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(attachmentsBucket).remove(paths);
      } catch (e) {
        // The row is already gone, so the file is unreachable through the app.
        // Surfacing a failure here would tell the user the retraction did not
        // work when the visible part of it did.
        // ignore: avoid_print
        print('⚠️ support attachment purge failed for $paths: $e');
      }
    }

    await _publish(ticketChannel(ticketId), ticketId);
  }

  /// Unread count per ticket, from the caller's own chat_inbox rows. The
  /// support inbox screen draws its badges from this rather than from the
  /// ticket table, which carries no per-user read state.
  Future<Map<String, int>> unreadByTicket() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _client
        .from('chat_inbox')
        .select('chat_id, unread_count')
        .eq('user_id', uid)
        .eq('chat_type', 'support');
    return {
      for (final r in (rows as List))
        r['chat_id'].toString(): (r['unread_count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Clears the unread state on the caller's own chat_inbox row for [ticketId].
  ///
  /// Web's trigger bumps `unread_count` on every agent reply and nothing on
  /// their side can know when the user actually looked, so the badge only ever
  /// went up. The one thing that cleared it was sending a reply — a user who
  /// read the answer and had nothing to add kept a badge forever. Written
  /// directly rather than via RPC: RLS already permits a user to update their
  /// own inbox row, and a stale badge is the only thing at stake.
  Future<void> markRead(String ticketId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client
          .from('chat_inbox')
          .update({
            'unread_count': 0,
            'has_unread': false,
            'last_read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('chat_id', ticketId)
          .eq('user_id', uid)
          .eq('chat_type', 'support');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ support markRead failed for $ticketId: $e');
    }
  }

  // ── Attachments ──────────────────────────────────────────────────────────

  /// Private bucket — nothing here is reachable by plain URL.
  static const String attachmentsBucket = 'support-attachments';

  /// Enforced by the bucket itself; mirrored here so we can refuse a file with
  /// a clear message instead of a storage error.
  static const int maxAttachmentBytes = 10 * 1024 * 1024;
  static const List<String> allowedMimeTypes = [
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'application/pdf',
  ];

  /// Uploads a file and posts it as a message on [ticketId].
  ///
  /// Two steps on purpose: the object goes to storage first, then
  /// attach_support_file writes both the message and the attachment row in one
  /// transaction. If the upload fails nothing is posted; if the RPC fails we
  /// delete the orphan rather than leave a file nobody can see.
  Future<void> sendAttachment({
    required String ticketId,
    required File file,
    required String fileName,
    required String mimeType,
  }) async {
    final bytes = await file.length();
    if (bytes > maxAttachmentBytes) {
      throw StateError('That file is larger than 10 MB.');
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw StateError('That file type is not supported.');
    }

    // The storage policy matches the FIRST path segment against the ticket id,
    // so this shape is mandatory, not a convention.
    final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
    final path =
        '$ticketId/${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}.$ext';

    await _client.storage.from(attachmentsBucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      await _client.rpc('attach_support_file', params: {
        'p_ticket_id': ticketId,
        'p_storage_path': path,
        'p_file_name': fileName,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes,
        // Passed explicitly, never derived from the role: staff filing their
        // own ticket are requesters too, and deriving it made a staff member's
        // screenshot render as though HangHut Support had sent it (#313).
        'p_sender': 'requester',
      });
    } catch (e) {
      try {
        await _client.storage.from(attachmentsBucket).remove([path]);
      } catch (_) {}
      rethrow;
    }

    await _publish(ticketChannel(ticketId), ticketId);
    await _publish(queueChannel, ticketId);
  }

  /// A short-lived URL for rendering. Private bucket, so this is the only way
  /// to display an attachment and the URL must not be cached beyond its life.
  Future<String?> signedUrl(String storagePath,
      {int expiresInSeconds = 3600}) async {
    try {
      return await _client.storage
          .from(attachmentsBucket)
          .createSignedUrl(storagePath, expiresInSeconds);
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ support signed URL failed for $storagePath: $e');
      return null;
    }
  }

  static String _randomSuffix() =>
      (DateTime.now().microsecondsSinceEpoch % 100000).toString();

  // ── Realtime ─────────────────────────────────────────────────────────────

  /// Fires whenever something on [ticketId] changed. Carries no content by
  /// design — the caller refetches.
  ///
  /// Strict id test on purpose: unlike web's agent console, which must accept
  /// any id because a queue signal is by definition about a thread it is not
  /// watching (#316), a requester client only ever cares about its own thread.
  Stream<void> watchTicket(String ticketId) async* {
    await _ably.init();
    final stream = _ably.getChannelStream(ticketChannel(ticketId));
    if (stream == null) return;
    yield* stream.where((ably.Message m) {
      final data = m.data;
      if (data is! Map) return false;
      return data['ticketId']?.toString() == ticketId;
    }).map((_) {});
  }

  /// Ably's connection state, for screens that must refetch after a gap.
  ///
  /// A signal transport gives no catch-up guarantee: anything published while
  /// this client was disconnected or suspended is simply not delivered when it
  /// comes back. A thread that relies on the signal alone therefore shows stale
  /// messages after every backgrounding, so the screen watches this and
  /// refetches on the way back up.
  Future<Stream<ably.ConnectionStateChange>?> connectionStates() async {
    await _ably.init();
    return _ably.getConnectionStateStream();
  }

  Future<void> _publish(String channel, String ticketId) async {
    try {
      await _ably.init();
      final ch = _ably.getChannel(channel);
      // Body-free forever. A payload carrying text on a channel a user trusts
      // because it says "HangHut Support" is branded impersonation, and the
      // publish key ships in the bundle. Never add a preview field here.
      await ch?.publish(name: 'message', data: {'ticketId': ticketId});
    } catch (e) {
      // Best-effort by design: the message is already committed and the push
      // notification is an independent nudge. A dropped publish costs one late
      // refresh, never a lost message.
      // ignore: avoid_print
      print('⚠️ support publish failed on $channel: $e');
    }
  }
}
