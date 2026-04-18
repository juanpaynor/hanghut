import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  // --- Reports ---

  /// Submit a report against a user, post, comment, table, or app issue.
  /// DB allows: 'user', 'post', 'table', 'message', 'app', 'other'.
  Future<bool> submitReport({
    required String targetType,
    required String targetId,
    required String reasonCategory,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      await _client.from('reports').insert({
        'reporter_id': user.id,
        'target_type': targetType,
        'target_id': targetId,
        'reason_category': reasonCategory,
        'description': description,
        'metadata': metadata ?? {},
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('❌ Error submitting report: $e');
      return false;
    }
  }

  // --- Blocks ---

  /// Block a user
  Future<bool> blockUser(String blockedUserId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      await _client.from('blocks').insert({
        'blocker_user_id': userId,
        'blocked_user_id': blockedUserId,
      });
      return true;
    } catch (e) {
      print('❌ Error blocking user: $e');
      return false;
    }
  }

  /// Unblock a user
  Future<bool> unblockUser(String blockedUserId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      await _client
          .from('blocks')
          .delete()
          .eq('blocker_user_id', userId)
          .eq('blocked_user_id', blockedUserId);
      return true;
    } catch (e) {
      print('❌ Error unblocking user: $e');
      return false;
    }
  }

  /// Get list of blocked users (with profile info)
  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('blocks')
          .select('''
            blocked_user_id,
            blocked_at,
            user:users!blocked_user_id (
              id,
              display_name,
              avatar_url,
              username
            )
          ''')
          .eq('blocker_user_id', userId)
          .order('blocked_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getting blocked users: $e');
      return [];
    }
  }

  /// Check if a user is blocked
  Future<bool> isUserBlocked(String targetUserId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _client
          .from('blocks')
          .select()
          .eq('blocker_user_id', userId)
          .eq('blocked_user_id', targetUserId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Get all blocked user IDs (both directions) via DB function.
  /// Use this for client-side filtering (map, search, etc.)
  Future<Set<String>> getBlockedUserIds() async {
    try {
      final response = await _client.rpc('get_blocked_user_ids');
      if (response == null) return {};
      return (response as List).map((e) => e.toString()).toSet();
    } catch (e) {
      print('❌ Error getting blocked user IDs: $e');
      return {};
    }
  }

  /// Reason categories for report UI
  static const List<Map<String, String>> reasonCategories = [
    {
      'key': 'spam',
      'label': 'Spam',
      'icon': '🚫',
      'desc': 'Unsolicited or repetitive content',
    },
    {
      'key': 'harassment',
      'label': 'Harassment',
      'icon': '😤',
      'desc': 'Bullying, threats, or intimidation',
    },
    {
      'key': 'hate_speech',
      'label': 'Hate Speech',
      'icon': '🚨',
      'desc': 'Discrimination or hateful content',
    },
    {
      'key': 'inappropriate',
      'label': 'Inappropriate Content',
      'icon': '⚠️',
      'desc': 'Nudity, violence, or graphic',
    },
    {
      'key': 'fake_account',
      'label': 'Fake Account',
      'icon': '🎭',
      'desc': 'Impersonation or fake identity',
    },
    {
      'key': 'scam',
      'label': 'Scam or Fraud',
      'icon': '💰',
      'desc': 'Misleading offers or fraud',
    },
    {
      'key': 'underage',
      'label': 'Underage User',
      'icon': '🔞',
      'desc': 'User appears to be under 18',
    },
    {
      'key': 'other',
      'label': 'Other',
      'icon': '📝',
      'desc': 'Something else not listed above',
    },
  ];
}
