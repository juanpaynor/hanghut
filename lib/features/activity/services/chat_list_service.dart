import 'package:bitemates/core/config/supabase_config.dart';

class ChatListService {
  static final ChatListService _instance = ChatListService._internal();
  factory ChatListService() => _instance;
  ChatListService._internal();

  /// Fetch active chats (Tables, DMs, Trips) from the unified view
  /// Supports pagination via [page] and [limit]
  Future<List<Map<String, dynamic>>> fetchActiveChats({
    int page = 0,
    int limit = 15,
  }) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return [];

      final start = page * limit;
      final end = start + limit - 1;

      final response = await SupabaseConfig.client
          .from('user_active_chats')
          .select()
          .eq('user_id', user.id)
          .order('has_unread', ascending: false)
          .order('last_activity_at', ascending: false)
          .range(start, end);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching active chats: $e');
      return [];
    }
  }

  /// Batched member avatars for group rows in the unified inbox.
  /// Returns { group_chat_id: [avatarUrl, ...up to 3] }. Only groups the
  /// current user belongs to are returned (enforced server-side).
  Future<Map<String, List<String>>> fetchGroupMemberAvatars(
    List<String> groupIds,
  ) async {
    if (groupIds.isEmpty) return {};
    try {
      final rows = await SupabaseConfig.client.rpc(
        'get_group_member_avatars',
        params: {'p_group_ids': groupIds},
      );
      final Map<String, List<String>> result = {};
      for (final row in (rows as List)) {
        final id = row['g_group_id']?.toString();
        if (id == null) continue;
        final urls = (row['g_avatar_urls'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            <String>[];
        result[id] = urls;
      }
      return result;
    } catch (e) {
      print('❌ Error fetching group member avatars: $e');
      return {};
    }
  }

  /// Mute / unmute a chat for the current user. Muted chats still accrue
  /// unread but produce no push / bell notification (enforced server-side in
  /// handle_new_message). Returns true on success.
  Future<bool> setChatMuted(String chatId, bool muted) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return false;
      await SupabaseConfig.client
          .from('chat_inbox')
          .update({'muted': muted})
          .eq('chat_id', chatId)
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      print('❌ Error setting chat muted=$muted: $e');
      return false;
    }
  }

  /// Whether a chat is currently muted for the current user.
  Future<bool> isChatMuted(String chatId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return false;
      final row = await SupabaseConfig.client
          .from('chat_inbox')
          .select('muted')
          .eq('chat_id', chatId)
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['muted'] == true;
    } catch (e) {
      print('❌ Error reading chat muted: $e');
      return false;
    }
  }

  /// Live total unread message count across ALL inbox entries (DMs + groups)
  /// for the current user. Emits on every chat_inbox change (Supabase realtime),
  /// so the chat bubble badge stays in sync without polling.
  Stream<int> totalUnreadStream() {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return Stream.value(0);
    return SupabaseConfig.client
        .from('chat_inbox')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map(
          (rows) => rows.fold<int>(
            0,
            (sum, r) => sum + ((r['unread_count'] as int?) ?? 0),
          ),
        );
  }

  /// One-shot total unread — used to seed the badge before the stream's first
  /// emission (and as a fallback if realtime is unavailable).
  Future<int> fetchTotalUnread() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return 0;
      final rows = await SupabaseConfig.client
          .from('chat_inbox')
          .select('unread_count')
          .eq('user_id', user.id);
      return (rows as List).fold<int>(
        0,
        (sum, r) => sum + ((r['unread_count'] as int?) ?? 0),
      );
    } catch (e) {
      print('❌ Error fetching total unread: $e');
      return 0;
    }
  }
}
