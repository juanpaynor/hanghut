import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/core/services/friends_going_service.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';

class TableMemberService {
  // Helper: get user display name for notification copy
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
                'status': 'joined',
                'requested_at': DateTime.now().toIso8601String(),
                'approved_at': DateTime.now().toIso8601String(),
                'joined_at': DateTime.now().toIso8601String(),
                'left_at': null,
              })
              .eq('table_id', tableId)
              .eq('user_id', user.id);

          // Notify friends asynchronously after re-join
          final tableTitle =
              (await SupabaseConfig.client
                  .from('tables')
                  .select('title')
                  .eq('id', tableId)
                  .maybeSingle())?['title'] ??
              'an activity';
          FriendsGoingService().notifyFriendsOfJoin(
            entityType: 'table',
            entityId: tableId,
            entityTitle: tableTitle,
          );

          return {'success': true, 'message': 'Successfully joined the table!'};
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

      // Get table info to check status, capacity, and approval setting
      final table = await SupabaseConfig.client
          .from('tables')
          .select(
            'status, max_guests, title, location_name, host_id, datetime, requires_approval, visibility, filters, latitude, longitude, max_join_distance_km',
          )
          .eq('id', tableId)
          .single();

      if (table['status'] != 'open') {
        return {
          'success': false,
          'message': 'This table is no longer accepting members',
        };
      }

      // ═══ Visibility Check ═══
      final visibility = table['visibility'] as String? ?? 'public';
      if (visibility == 'followers_only') {
        // Check if user follows the host
        final hostId = table['host_id'] as String;
        final followCheck = await SupabaseConfig.client
            .from('follows')
            .select('follower_id')
            .eq('follower_id', user.id)
            .eq('following_id', hostId)
            .maybeSingle();
        if (followCheck == null) {
          return {
            'success': false,
            'message':
                'This hangout is for followers only. Follow the host first!',
          };
        }
      }

      // ═══ Location Distance Check ═══
      final tableLat = (table['latitude'] as num?)?.toDouble();
      final tableLng = (table['longitude'] as num?)?.toDouble();
      final maxDistKm =
          (table['max_join_distance_km'] as num?)?.toDouble() ??
          100.0; // default 100km
      if (tableLat != null && tableLng != null) {
        try {
          bool locationPermissionOk = false;
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            locationPermissionOk = true;
          }
          if (locationPermissionOk) {
            Position? pos;
            try {
              pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.medium,
                  timeLimit: Duration(seconds: 8),
                ),
              );
            } catch (_) {
              // Timed out or no fresh fix — use last known as fallback
              pos = await Geolocator.getLastKnownPosition();
            }
            if (pos == null) {
              // Can't determine location — allow join rather than block
              debugPrint('⚠️ Location unavailable, skipping distance check');
            } else {
              final distanceMeters = Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                tableLat,
                tableLng,
              );
              final distanceKm = distanceMeters / 1000.0;
              if (distanceKm > maxDistKm) {
                return {
                  'success': false,
                  'message':
                      'You are too far away to join this hangout (${distanceKm.toStringAsFixed(0)} km away, max ${maxDistKm.toStringAsFixed(0)} km).',
                };
              }
            } // end else (pos != null)
          }
        } catch (e) {
          debugPrint('⚠️ Location check skipped: $e');
          // Non-fatal: if location check fails, allow join
        }
      }

      // ═══ Advanced Filter Enforcement ═══
      final rawFilters = table['filters'];
      if (rawFilters != null && rawFilters is Map && rawFilters.isNotEmpty) {
        final filters = Map<String, dynamic>.from(rawFilters);
        final enforcement = filters['enforcement'] as String? ?? 'soft';

        if (enforcement == 'hard') {
          // Fetch user profile for comparison
          final userProfile = await SupabaseConfig.client
              .from('users')
              .select('gender_identity, date_of_birth')
              .eq('id', user.id)
              .single();

          // Gender check
          final genderFilter = filters['gender'] as String?;
          if (genderFilter != null && genderFilter != 'everyone') {
            final userGender =
                (userProfile['gender_identity'] as String?)?.toLowerCase() ??
                '';
            bool genderMatch = false;
            if (genderFilter == 'women_only' && userGender == 'female')
              genderMatch = true;
            if (genderFilter == 'men_only' && userGender == 'male')
              genderMatch = true;
            if (genderFilter == 'nonbinary_only' && userGender == 'non-binary')
              genderMatch = true;
            if (!genderMatch) {
              return {
                'success': false,
                'message':
                    'This hangout has a gender requirement you don\'t match.',
              };
            }
          }

          // Age check
          final ageMin = filters['age_min'] as int?;
          final ageMax = filters['age_max'] as int?;
          if (ageMin != null || ageMax != null) {
            final dobStr = userProfile['date_of_birth'] as String?;
            if (dobStr != null) {
              final dob = DateTime.tryParse(dobStr);
              if (dob != null) {
                final now = DateTime.now();
                int age = now.year - dob.year;
                if (now.month < dob.month ||
                    (now.month == dob.month && now.day < dob.day)) {
                  age--;
                }
                if ((ageMin != null && age < ageMin) ||
                    (ageMax != null && age > ageMax)) {
                  return {
                    'success': false,
                    'message':
                        'This hangout has an age requirement ($ageMin–$ageMax) you don\'t match.',
                  };
                }
              }
            }
          }
        }
      }

      final requiresApproval = table['requires_approval'] == true;

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

      if (requiresApproval) {
        // Host approval required — insert as pending
        await SupabaseConfig.client.from('table_members').insert({
          'table_id': tableId,
          'user_id': user.id,
          'role': 'member',
          'status': 'pending',
          'requested_at': DateTime.now().toIso8601String(),
        });

        // Send notification to host
        final hostId = table['host_id'] as String;
        final userName = await _getUserDisplayName(user.id);
        try {
          await SupabaseConfig.client.from('notifications').insert({
            'user_id': hostId,
            'actor_id': user.id,
            'type': 'join_request',
            'entity_id': tableId,
            'title': '$userName wants to join',
            'body': table['title'] ?? 'Your table',
            'metadata': {'table_id': tableId},
          });
        } catch (_) {
          // Non-critical
        }

        return {
          'success': true,
          'message': 'Request sent! The host will review it.',
        };
      }

      // No approval required — auto-join
      await SupabaseConfig.client.from('table_members').insert({
        'table_id': tableId,
        'user_id': user.id,
        'role': 'member',
        'status': 'joined',
        'joined_at': DateTime.now().toIso8601String(),
      });

      // Schedule a reminder notification for 30 min before event
      if (table['datetime'] != null) {
        NotificationService().scheduleEventReminder(
          tableId: tableId,
          title: table['title'] ?? 'Event',
          venueName: table['location_name'] ?? '',
          eventTime: DateTime.parse(table['datetime']),
        );
      }

      // Notify friends who are already in this table
      final tableTitle = table['title'] ?? 'an activity';
      FriendsGoingService().notifyFriendsOfJoin(
        entityType: 'table',
        entityId: tableId,
        entityTitle: tableTitle,
      );

      // Award XP for joining an event
      BadgeService()
          .incrementStats(user.id, attended: 1, baseXp: XpValues.joinEvent)
          .ignore();

      return {'success': true, 'message': 'Successfully joined the table!'};
    } catch (e) {
      debugPrint('⚠️ Error joining table: $e');
      return {
        'success': false,
        'message': 'Failed to join table. Please try again.',
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

      // Cancel any scheduled reminder
      NotificationService().cancelEventReminder(tableId);

      return {'success': true, 'message': 'You have left the table'};
    } catch (e) {
      debugPrint('⚠️ Error leaving table: $e');
      return {
        'success': false,
        'message': 'Failed to leave table. Please try again.',
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

      // Schedule a reminder for the approved user
      try {
        final table = await SupabaseConfig.client
            .from('tables')
            .select('title, location_name, datetime')
            .eq('id', tableId)
            .single();

        if (table['datetime'] != null) {
          NotificationService().scheduleEventReminder(
            tableId: tableId,
            title: table['title'] ?? 'Event',
            venueName: table['location_name'] ?? '',
            eventTime: DateTime.parse(table['datetime']),
          );
        }
      } catch (_) {
        // Non-critical — don't fail the approval if reminder fails
      }

      return {'success': true, 'message': 'Request approved'};
    } catch (e) {
      debugPrint('⚠️ Error approving request: $e');
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
      debugPrint('⚠️ Error rejecting request: $e');
      return {'success': false, 'message': 'Failed to reject request'};
    }
  }

  // Remove a member (host only)
  /// Host invites a user directly — skips approval, sets status to 'joined'
  Future<Map<String, dynamic>> inviteUserToTable(
    String tableId,
    String userId,
  ) async {
    try {
      final existing = await SupabaseConfig.client
          .from('table_members')
          .select('status')
          .eq('table_id', tableId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        final status = existing['status'] as String;
        if (status == 'joined' ||
            status == 'approved' ||
            status == 'attended') {
          return {'success': false, 'message': 'User is already a member'};
        }
        // Re-activate removed/left member
        await SupabaseConfig.client
            .from('table_members')
            .update({
              'status': 'joined',
              'joined_at': DateTime.now().toIso8601String(),
              'approved_at': DateTime.now().toIso8601String(),
              'left_at': null,
            })
            .eq('table_id', tableId)
            .eq('user_id', userId);
      } else {
        await SupabaseConfig.client.from('table_members').insert({
          'table_id': tableId,
          'user_id': userId,
          'status': 'joined',
          'role': 'member',
          'joined_at': DateTime.now().toIso8601String(),
          'approved_at': DateTime.now().toIso8601String(),
        });
      }
      return {'success': true, 'message': 'User added to hangout'};
    } catch (e) {
      debugPrint('⚠️ Error inviting user: $e');
      return {'success': false, 'message': 'Failed to invite user'};
    }
  }

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
      debugPrint('⚠️ Error removing member: $e');
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
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('table_id', tableId)
          .eq('status', 'pending')
          .order('requested_at', ascending: true);

      return List<Map<String, dynamic>>.from(requests);
    } catch (e) {
      debugPrint('⚠️ Error getting pending requests: $e');
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
      debugPrint('⚠️ Error getting table members: $e');
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
      debugPrint('⚠️ Error checking membership: $e');
      return null;
    }
  }

  /// Accept an invite (invited user accepts the pending membership)
  Future<Map<String, dynamic>> acceptInvite(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await SupabaseConfig.client
          .from('table_members')
          .update({
            'status': 'joined',
            'approved_at': DateTime.now().toIso8601String(),
            'joined_at': DateTime.now().toIso8601String(),
          })
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .eq('status', 'pending');

      // Schedule event reminder
      try {
        final table = await SupabaseConfig.client
            .from('tables')
            .select('title, location_name, datetime')
            .eq('id', tableId)
            .single();

        if (table['datetime'] != null) {
          NotificationService().scheduleEventReminder(
            tableId: tableId,
            title: table['title'] ?? 'Event',
            venueName: table['location_name'] ?? '',
            eventTime: DateTime.parse(table['datetime']),
          );
        }
      } catch (_) {}

      return {'success': true, 'message': 'You\'re in! 🎉'};
    } catch (e) {
      debugPrint('⚠️ Error accepting invite: $e');
      return {'success': false, 'message': 'Failed to accept invite'};
    }
  }

  /// Decline an invite
  Future<Map<String, dynamic>> declineInvite(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await SupabaseConfig.client
          .from('table_members')
          .update({'status': 'declined'})
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .eq('status', 'pending');

      return {'success': true, 'message': 'Invite declined'};
    } catch (e) {
      debugPrint('⚠️ Error declining invite: $e');
      return {'success': false, 'message': 'Failed to decline invite'};
    }
  }

  /// Mute a participant in a table chat (host only)
  Future<Map<String, dynamic>> muteParticipant(
    String tableId,
    String userId,
  ) async {
    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({'is_muted': true})
          .eq('table_id', tableId)
          .eq('user_id', userId);
      return {'success': true, 'message': 'User muted'};
    } catch (e) {
      debugPrint('⚠️ Error muting participant: $e');
      return {'success': false, 'message': 'Failed to mute user'};
    }
  }

  /// Unmute a participant in a table chat (host only)
  Future<Map<String, dynamic>> unmuteParticipant(
    String tableId,
    String userId,
  ) async {
    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({'is_muted': false})
          .eq('table_id', tableId)
          .eq('user_id', userId);
      return {'success': true, 'message': 'User unmuted'};
    } catch (e) {
      debugPrint('⚠️ Error unmuting participant: $e');
      return {'success': false, 'message': 'Failed to unmute user'};
    }
  }

  /// Check if current user is muted in a table
  Future<bool> isCurrentUserMuted(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return false;
      final row = await SupabaseConfig.client
          .from('table_members')
          .select('is_muted')
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['is_muted'] == true;
    } catch (e) {
      return false;
    }
  }
}
