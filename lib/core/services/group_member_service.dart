import 'package:bitemates/core/config/supabase_config.dart';

class GroupMemberService {
  // ═══════════════════════════════════════════════
  // JOIN / LEAVE
  // ═══════════════════════════════════════════════

  /// Join a group. Public = auto-approve, Private = pending, Hidden = not allowed.
  Future<Map<String, dynamic>> joinGroup(String groupId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Check existing membership
      final existing = await SupabaseConfig.client
          .from('group_members')
          .select('status, role')
          .eq('group_id', groupId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        final status = existing['status'] as String;
        if (status == 'approved') {
          return {'success': false, 'message': 'You are already a member'};
        }
        if (status == 'pending') {
          return {'success': false, 'message': 'Your request is pending approval'};
        }
        if (status == 'banned') {
          return {'success': false, 'message': 'You have been banned from this group'};
        }
      }

      // Get group privacy setting
      final group = await SupabaseConfig.client
          .from('groups')
          .select('privacy, name, created_by')
          .eq('id', groupId)
          .single();

      final privacy = group['privacy'] as String;

      if (privacy == 'hidden') {
        return {'success': false, 'message': 'This group is invite-only'};
      }

      final isPublic = privacy == 'public';
      final memberStatus = isPublic ? 'approved' : 'pending';

      if (existing != null) {
        // Re-join (was previously not approved or left — update existing row)
        await SupabaseConfig.client
            .from('group_members')
            .update({
              'status': memberStatus,
              'role': 'member',
              'joined_at': isPublic
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
              'last_read_at': isPublic
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
            })
            .eq('group_id', groupId)
            .eq('user_id', user.id);
      } else {
        // New membership
        await SupabaseConfig.client.from('group_members').insert({
          'group_id': groupId,
          'user_id': user.id,
          'role': 'member',
          'status': memberStatus,
          'joined_at': isPublic
              ? DateTime.now().toUtc().toIso8601String()
              : null,
          'last_read_at': isPublic
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        });
      }

      // If private: notify the group owner
      if (!isPublic) {
        try {
          final userName = await _getUserDisplayName(user.id);
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': group['created_by'],
            'actor_id': user.id,
            'type': 'group_join_request',
            'entity_id': groupId,
            'title': '$userName wants to join',
            'body': group['name'] ?? 'Your group',
            'metadata': {'group_id': groupId},
          });
        } catch (_) {}
      }

      return {
        'success': true,
        'message': isPublic
            ? 'Welcome to the group! 🎉'
            : 'Request sent! The admin will review it.',
        'status': memberStatus,
      };
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error joining group - $e');
      return {'success': false, 'message': 'Failed to join group: $e'};
    }
  }

  /// Leave a group
  Future<Map<String, dynamic>> leaveGroup(String groupId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await SupabaseConfig.client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', user.id);

      return {'success': true, 'message': 'You have left the group'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error leaving group - $e');
      return {'success': false, 'message': 'Failed to leave group: $e'};
    }
  }

  // ═══════════════════════════════════════════════
  // ADMIN ACTIONS
  // ═══════════════════════════════════════════════

  /// Approve a join request (admin/owner only)
  Future<Map<String, dynamic>> approveRequest(
      String groupId, String userId) async {
    try {
      await SupabaseConfig.client
          .from('group_members')
          .update({
            'status': 'approved',
            'joined_at': DateTime.now().toUtc().toIso8601String(),
            'last_read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .eq('status', 'pending');

      // Notify the user they were approved
      try {
        final group = await SupabaseConfig.client
            .from('groups')
            .select('name')
            .eq('id', groupId)
            .single();

        await SupabaseConfig.client.from('notifications').insert({
          'user_id': userId,
          'actor_id': SupabaseConfig.client.auth.currentUser!.id,
          'type': 'group_approved',
          'entity_id': groupId,
          'title': 'You\'re in! 🎉',
          'body': 'Your request to join ${group['name']} was approved',
          'metadata': {'group_id': groupId},
        });
      } catch (_) {}

      return {'success': true, 'message': 'Member approved'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error approving request - $e');
      return {'success': false, 'message': 'Failed to approve request'};
    }
  }

  /// Reject a join request
  Future<Map<String, dynamic>> rejectRequest(
      String groupId, String userId) async {
    try {
      await SupabaseConfig.client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .eq('status', 'pending');

      return {'success': true, 'message': 'Request rejected'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error rejecting request - $e');
      return {'success': false, 'message': 'Failed to reject request'};
    }
  }

  /// Remove/kick a member
  Future<Map<String, dynamic>> removeMember(
      String groupId, String userId) async {
    try {
      await SupabaseConfig.client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);

      return {'success': true, 'message': 'Member removed'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error removing member - $e');
      return {'success': false, 'message': 'Failed to remove member'};
    }
  }

  /// Ban a member
  Future<Map<String, dynamic>> banMember(
      String groupId, String userId) async {
    try {
      await SupabaseConfig.client
          .from('group_members')
          .update({'status': 'banned'})
          .eq('group_id', groupId)
          .eq('user_id', userId);

      return {'success': true, 'message': 'Member banned'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error banning member - $e');
      return {'success': false, 'message': 'Failed to ban member'};
    }
  }

  /// Update a member's role (promote/demote)
  Future<Map<String, dynamic>> updateRole(
      String groupId, String userId, String newRole) async {
    try {
      await SupabaseConfig.client
          .from('group_members')
          .update({'role': newRole})
          .eq('group_id', groupId)
          .eq('user_id', userId);

      return {'success': true, 'message': 'Role updated to $newRole'};
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error updating role - $e');
      return {'success': false, 'message': 'Failed to update role'};
    }
  }

  // ═══════════════════════════════════════════════
  // READ
  // ═══════════════════════════════════════════════

  /// Get all approved members of a group
  Future<List<Map<String, dynamic>>> getMembers(String groupId) async {
    try {
      final members = await SupabaseConfig.client
          .from('group_members')
          .select('''
            *,
            users:user_id (
              id,
              display_name,
              bio,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('group_id', groupId)
          .eq('status', 'approved')
          .order('joined_at', ascending: true);

      return List<Map<String, dynamic>>.from(members);
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error fetching members - $e');
      return [];
    }
  }

  /// Get pending join requests (admin view)
  Future<List<Map<String, dynamic>>> getPendingRequests(String groupId) async {
    try {
      final requests = await SupabaseConfig.client
          .from('group_members')
          .select('''
            *,
            users:user_id (
              id,
              display_name,
              bio,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('group_id', groupId)
          .eq('status', 'pending')
          .order('joined_at', ascending: true);

      return List<Map<String, dynamic>>.from(requests);
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error fetching pending requests - $e');
      return [];
    }
  }

  /// Check current user's membership status in a group
  Future<Map<String, dynamic>?> getUserMembershipStatus(String groupId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return null;

      final membership = await SupabaseConfig.client
          .from('group_members')
          .select('status, role')
          .eq('group_id', groupId)
          .eq('user_id', user.id)
          .maybeSingle();

      return membership;
    } catch (e) {
      print('❌ GROUP MEMBER SERVICE: Error checking membership - $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════

  Future<String> _getUserDisplayName(String userId) async {
    try {
      final user = await SupabaseConfig.client
          .from('users')
          .select('display_name')
          .eq('id', userId)
          .single();
      return user['display_name'] ?? 'Someone';
    } catch (_) {
      return 'Someone';
    }
  }
}
