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
          .order('last_activity_at', ascending: false)
          .range(start, end);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching active chats: $e');
      return [];
    }
  }
}
