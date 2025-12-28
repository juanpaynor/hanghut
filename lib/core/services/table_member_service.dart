import 'package:bitemates/core/config/supabase_config.dart';

class TableMemberService {
  // Join a table (instant join)
  Future<Map<String, dynamic>> joinTable(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Check if user is already a member
      final existingMember = await SupabaseConfig.client
          .from('table_members')
          .select()
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingMember != null) {
        return {
          'success': false,
          'message': 'You are already a member of this table',
        };
      }

      // Get table info to check status and capacity
      final table = await SupabaseConfig.client
          .from('tables')
          .select('status, max_guests')
          .eq('id', tableId)
          .single();

      if (table['status'] != 'open') {
        return {
          'success': false,
          'message': 'This table is no longer accepting members',
        };
      }

      // Count current members
      final currentMembers = await SupabaseConfig.client
          .from('table_members')
          .select('id')
          .eq('table_id', tableId)
          .inFilter('status', ['approved', 'joined', 'attended']);

      final maxGuests = table['max_guests'] as int;
      final currentCount = currentMembers.length;

      if (currentCount >= maxGuests) {
        return {'success': false, 'message': 'This table is full'};
      }

      // Add member with approved status (instant join)
      await SupabaseConfig.client.from('table_members').insert({
        'table_id': tableId,
        'user_id': user.id,
        'role': 'member',
        'status': 'approved',
        'requested_at': DateTime.now().toIso8601String(),
        'approved_at': DateTime.now().toIso8601String(),
        'joined_at': DateTime.now().toIso8601String(),
      });

      return {'success': true, 'message': 'Successfully joined the table!'};
    } catch (e) {
      print('❌ Error joining table: $e');
      return {
        'success': false,
        'message': 'Failed to join table: ${e.toString()}',
      };
    }
  }

  // Leave a table
  Future<Map<String, dynamic>> leaveTable(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update member status to 'left'
      await SupabaseConfig.client
          .from('table_members')
          .update({
            'status': 'left',
            'left_at': DateTime.now().toIso8601String(),
          })
          .eq('table_id', tableId)
          .eq('user_id', user.id);

      return {'success': true, 'message': 'You have left the table'};
    } catch (e) {
      print('❌ Error leaving table: $e');
      return {
        'success': false,
        'message': 'Failed to leave table: ${e.toString()}',
      };
    }
  }

  // Approve a join request (host only)
  Future<Map<String, dynamic>> approveRequest(
    String tableId,
    String userId,
  ) async {
    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({
            'status': 'approved',
            'approved_at': DateTime.now().toIso8601String(),
            'joined_at': DateTime.now().toIso8601String(),
          })
          .eq('table_id', tableId)
          .eq('user_id', userId)
          .eq('status', 'pending');

      return {'success': true, 'message': 'Request approved'};
    } catch (e) {
      print('❌ Error approving request: $e');
      return {'success': false, 'message': 'Failed to approve request'};
    }
  }

  // Reject a join request (host only)
  Future<Map<String, dynamic>> rejectRequest(
    String tableId,
    String userId,
  ) async {
    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({'status': 'declined'})
          .eq('table_id', tableId)
          .eq('user_id', userId)
          .eq('status', 'pending');

      return {'success': true, 'message': 'Request rejected'};
    } catch (e) {
      print('❌ Error rejecting request: $e');
      return {'success': false, 'message': 'Failed to reject request'};
    }
  }

  // Remove a member (host only)
  Future<Map<String, dynamic>> removeMember(
    String tableId,
    String userId,
  ) async {
    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({
            'status': 'left',
            'left_at': DateTime.now().toIso8601String(),
          })
          .eq('table_id', tableId)
          .eq('user_id', userId);

      return {'success': true, 'message': 'Member removed'};
    } catch (e) {
      print('❌ Error removing member: $e');
      return {'success': false, 'message': 'Failed to remove member'};
    }
  }

  // Get pending requests for a table (host only)
  Future<List<Map<String, dynamic>>> getPendingRequests(String tableId) async {
    try {
      final requests = await SupabaseConfig.client
          .from('table_members')
          .select('''
            *,
            users:user_id (
              id,
              display_name,
              bio,
              trust_score
            )
          ''')
          .eq('table_id', tableId)
          .eq('status', 'pending')
          .order('requested_at', ascending: true);

      return List<Map<String, dynamic>>.from(requests);
    } catch (e) {
      print('❌ Error getting pending requests: $e');
      return [];
    }
  }

  // Get all members of a table
  Future<List<Map<String, dynamic>>> getTableMembers(String tableId) async {
    try {
      final members = await SupabaseConfig.client
          .from('table_members')
          .select('''
            *,
            users:user_id (
              id,
              display_name,
              bio,
              trust_score
            )
          ''')
          .eq('table_id', tableId)
          .inFilter('status', ['approved', 'joined', 'attended'])
          .order('joined_at', ascending: true);

      return List<Map<String, dynamic>>.from(members);
    } catch (e) {
      print('❌ Error getting table members: $e');
      return [];
    }
  }

  // Check if user is a member of a table
  Future<Map<String, dynamic>?> getUserMembershipStatus(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return null;

      final membership = await SupabaseConfig.client
          .from('table_members')
          .select('status, role')
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .maybeSingle();

      return membership;
    } catch (e) {
      print('❌ Error checking membership: $e');
      return null;
    }
  }
}
