import 'package:bitemates/core/config/supabase_config.dart';

class TableMemberService {
  // Join a table (sends pending request for host approval)
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
        final status = existingMember['status'];
        // Allow re-requesting if previously left or declined/cancelled
        if (status == 'left' || status == 'declined' || status == 'cancelled') {
          await SupabaseConfig.client
              .from('table_members')
              .update({
                'status': 'pending',
                'requested_at': DateTime.now().toIso8601String(),
                'approved_at': null,
                'joined_at': null,
                'left_at': null,
              })
              .eq('table_id', tableId)
              .eq('user_id', user.id);

          return {
            'success': true,
            'message': 'Request sent! Waiting for host approval.',
          };
        }

        if (status == 'pending') {
          return {
            'success': false,
            'message': 'You already have a pending request',
          };
        }

        return {
          'success': false,
          'message': 'You are already a member of this table',
        };
      }

      // Get table info to check status and capacity
      final table = await SupabaseConfig.client
          .from('tables')
          .select('status, max_guests, title, location_name, host_id')
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

      // Add member with pending status (host must approve)
      await SupabaseConfig.client.from('table_members').insert({
        'table_id': tableId,
        'user_id': user.id,
        'role': 'member',
        'status': 'pending',
        'requested_at': DateTime.now().toIso8601String(),
      });

      // Notification handled by database trigger (handle_table_join)

      return {
        'success': true,
        'message': 'Request sent! Waiting for host approval.',
      };
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

      // Notification now handled by database trigger (handle_join_approval)

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
              trust_score,
              avatar_url,
              user_photos (
                photo_url,
                is_primary
              )
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
