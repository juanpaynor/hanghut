import 'package:bitemates/core/config/supabase_config.dart';

/// Service to check and handle user account status
class AccountStatusService {
  /// Check user's current status from database
  /// Returns status: 'active', 'suspended', 'banned', or 'deleted'
  static Future<Map<String, dynamic>> checkStatus() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        print('⚠️ STATUS CHECK: No user ID found');
        return {'status': 'unknown', 'reason': null};
      }

      print('🔍 STATUS CHECK: Checking status for user $userId');

      final response = await SupabaseConfig.client
          .from('users')
          .select('status, status_reason, deleted_at')
          .eq('id', userId)
          .single();

      print('✅ STATUS CHECK: Response = $response');

      final status = response['status'] ?? 'active';
      print('📊 STATUS CHECK: User status = $status');

      return {
        'status': status,
        'reason': response['status_reason'],
        'deleted_at': response['deleted_at'],
      };
    } catch (e) {
      print('❌ Error checking account status: $e');
      return {'status': 'error', 'reason': null};
    }
  }

  /// Check if user is allowed to access the app
  /// Returns true if active, false if suspended/banned/deleted
  static Future<bool> isAccountActive() async {
    final status = await checkStatus();
    return status['status'] == 'active';
  }

  /// Get user-friendly message for status
  static String getStatusMessage(String status) {
    switch (status) {
      case 'suspended':
        return 'Your account has been temporarily suspended.';
      case 'banned':
        return 'Your account has been permanently banned.';
      case 'deleted':
        return 'This account has been deleted.';
      default:
        return 'There was an issue with your account.';
    }
  }
}
