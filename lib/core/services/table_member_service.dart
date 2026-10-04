import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/core/services/friends_going_service.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';
import 'package:bitemates/features/map/models/hangout_social_proof.dart';
import 'package:bitemates/features/activity/models/invite_rules.dart';

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
              'a hangout';
          FriendsGoingService().notifyFriendsOfJoin(
            entityType: 'table',
            entityId: tableId,
            entityTitle: tableTitle,
          );

          return {'success': true, 'message': 'Successfully joined the hangout!'};
        }

        if (status == 'pending') {
          return {
            'success': false,
            'message': 'You already have a pending request',
          };
        }

        // 'interested' and 'invited' both hold NO spot, so tapping Join has
        // to run the real join path — capacity, approval and distance all
        // still have to be checked. Falling through instead of returning is
        // deliberate: the writes below upsert on (table_id, user_id), so the
        // existing row is upgraded in place rather than colliding with the
        // unique constraint.
        //
        // 'invited' is in `member_status_type` but was handled nowhere, so it
        // fell into the branch below and told an invited user "You are already
        // in this hangout" — refusing the one action the invite asked them to
        // take. Any invite flow is dead until this falls through.
        if (status != 'interested' && status != 'invited') {
          return {
            'success': false,
            'message': 'You are already in this hangout',
          };
        }
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
          'message': 'This hangout is no longer accepting members',
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
      final locationName = (table['location_name'] as String?)?.trim();
      // A TBD / location-less hangout has no real place to be near, so it must
      // NOT enforce a join radius. These are stored either as 'TBD' with the
      // host's incidental coords, or at null-island (0,0) when the host had no
      // fix — and 0,0 is ~thousands of km from any real user, which would
      // otherwise reject EVERY joiner ("no one can join").
      final hasFixedLocation =
          tableLat != null &&
          tableLng != null &&
          !(tableLat == 0 && tableLng == 0) &&
          (locationName == null || locationName.toUpperCase() != 'TBD');
      final maxDistKm =
          (table['max_join_distance_km'] as num?)?.toDouble() ??
          500.0; // default 500km (was 100; Rich, 2026-09-21)
      if (hasFixedLocation) {
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
        return {'success': false, 'message': 'This hangout is full'};
      }

      if (requiresApproval) {
        // Host approval required — insert as pending
        await SupabaseConfig.client.from('table_members').upsert({
          'table_id': tableId,
          'user_id': user.id,
          'role': 'member',
          'status': 'pending',
          'requested_at': DateTime.now().toIso8601String(),
        }, onConflict: 'table_id,user_id');

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
            'body': table['title'] ?? 'Your hangout',
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
      await SupabaseConfig.client.from('table_members').upsert({
        'table_id': tableId,
        'user_id': user.id,
        'role': 'member',
        'status': 'joined',
        'joined_at': DateTime.now().toIso8601String(),
        'left_at': null,
      }, onConflict: 'table_id,user_id');

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
      final tableTitle = table['title'] ?? 'a hangout';
      FriendsGoingService().notifyFriendsOfJoin(
        entityType: 'table',
        entityId: tableId,
        entityTitle: tableTitle,
      );

      // Award XP for joining an event
      BadgeService()
          .incrementStats(user.id, attended: 1, baseXp: XpValues.joinEvent)
          .ignore();

      return {'success': true, 'message': 'Successfully joined the hangout!'};
    } catch (e) {
      debugPrint('⚠️ Error joining table: $e');
      return {
        'success': false,
        'message': 'Failed to join hangout. Please try again.',
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

      return {'success': true, 'message': 'You have left the hangout'};
    } catch (e) {
      debugPrint('⚠️ Error leaving table: $e');
      return {
        'success': false,
        'message': 'Failed to leave hangout. Please try again.',
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

  /// Invite a user to a hangout. They must accept before they are a member.
  ///
  /// This used to write `status: 'joined'` with no consent step and no
  /// notification — anyone already in a hangout could add you to it and you
  /// would simply find yourself in a group chat with strangers. For a feature
  /// whose job is introducing people who do not know each other, that is not a
  /// detail. It now writes `'invited'` and tells them, which is also the state
  /// the invite surfaces read.
  ///
  /// An invite holds NO spot: every capacity and roster query filters on
  /// ('approved','joined','attended'), so inviting ten people to a four-seat
  /// hangout does not fill it. Capacity is enforced when they accept, in
  /// [joinTable].
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
        if (status == 'invited') {
          return {'success': false, 'message': 'They have already been invited'};
        }
        // Re-invite someone who left, declined or was removed.
        await SupabaseConfig.client
            .from('table_members')
            .update({
              'status': 'invited',
              'requested_at': DateTime.now().toIso8601String(),
              'approved_at': null,
              'joined_at': null,
              'left_at': null,
            })
            .eq('table_id', tableId)
            .eq('user_id', userId);
      } else {
        await SupabaseConfig.client.from('table_members').insert({
          'table_id': tableId,
          'user_id': userId,
          'status': 'invited',
          'role': 'member',
          'requested_at': DateTime.now().toIso8601String(),
        });
      }

      await notifyOfInvite(tableId: tableId, inviteeId: userId);
      return {'success': true, 'message': 'Invite sent'};
    } catch (e) {
      debugPrint('⚠️ Error inviting user: $e');
      return {'success': false, 'message': 'Failed to invite user'};
    }
  }

  /// Tells someone they have been invited — bell + push.
  ///
  /// Mirrors the create-time path in `TableService.createTable` so both routes
  /// produce the same `hangout_invite` notification, and is public because the
  /// cohort promotion in Phase 1 sends the same thing for several people at
  /// once. Never throws: an invite that saved but failed to notify is still a
  /// real invite, and the recipient will see it in the Hangouts tab.
  Future<void> notifyOfInvite({
    required String tableId,
    required String inviteeId,
  }) async {
    // Respect the opt-out before writing anything. An absent key reads as
    // consent (see wants_notification), so this only suppresses a deliberate
    // "no" — and a failure to check is treated as consent too, because losing
    // an invite is worse than one notification someone muted.
    try {
      final wants = await SupabaseConfig.client.rpc(
        'wants_notification',
        params: {'p_user_id': inviteeId, 'p_key': 'hangout_invites'},
      );
      if (wants == false) {
        debugPrint('🔕 $inviteeId has muted hangout invites — not notifying');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Could not check notification preference: $e');
    }

    final actorId = SupabaseConfig.client.auth.currentUser?.id;
    String title = 'a hangout';
    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select('title')
          .eq('id', tableId)
          .maybeSingle();
      final raw = table?['title']?.toString();
      if (raw != null && raw.trim().isNotEmpty) title = raw;
    } catch (_) {}

    final actorName =
        actorId == null ? 'Someone' : await _getUserDisplayName(actorId);
    const heading = "You're Invited! 🎉";
    final body = '$actorName invited you to "$title"';

    try {
      await SupabaseConfig.client.from('notifications').insert({
        'user_id': inviteeId,
        'actor_id': actorId,
        'type': 'hangout_invite',
        'entity_id': tableId,
        'title': heading,
        'body': body,
        'metadata': {'table_id': tableId},
      });
    } catch (e) {
      debugPrint('⚠️ Failed to insert invite notification: $e');
    }

    // No send-push call: the row above already produces the push via
    // handle_notifications_webhook -> pgmq -> process-push-queue, carrying
    // data.type = 'hangout_invite' which the app routes. Invoking send-push
    // as well is how the rest of this file ended up sending duplicates.
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

  /// Accept an invite.
  ///
  /// Matches BOTH statuses an invite can legitimately have. It used to scope on
  /// `status = 'pending'` alone, which is what create-time invites write — so
  /// against a `status = 'invited'` row it matched zero rows. A 0-row PostgREST
  /// update does not error, so this returned `success: true` having saved
  /// nothing, and the user was told "You're in!" while nothing happened.
  ///
  /// `.select()` is what makes that detectable: it returns the rows actually
  /// updated, so an empty list is a failed accept rather than a silent one.
  Future<Map<String, dynamic>> acceptInvite(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final updated = await SupabaseConfig.client
          .from('table_members')
          .update({
            'status': 'joined',
            'approved_at': DateTime.now().toIso8601String(),
            'joined_at': DateTime.now().toIso8601String(),
          })
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .inFilter('status', openInviteStatuses)
          .select('status');

      if (updated.isEmpty) {
        // No open invite: already answered, already a member, or withdrawn.
        return {
          'success': false,
          'message': 'That invite is no longer open',
        };
      }

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

  /// Decline an invite.
  ///
  /// Deliberately NOT a delete: `declined` is what stops the same hangout being
  /// offered again, and [joinTable] still lets someone change their mind later
  /// (it treats `declined` as re-joinable). Same two fixes as [acceptInvite] —
  /// both invite statuses, and a 0-row update is a failure.
  Future<Map<String, dynamic>> declineInvite(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final updated = await SupabaseConfig.client
          .from('table_members')
          .update({'status': 'declined'})
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .inFilter('status', openInviteStatuses)
          .select('status');

      if (updated.isEmpty) {
        return {
          'success': false,
          'message': 'That invite is no longer open',
        };
      }

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

  // ───────────────────────── Interested ─────────────────────────
  // Joining a hangout means committing to a place, a time and strangers. Over
  // the last 90 days that ask converted 19 distinct people while 63% of
  // hangouts got nobody, so "Interested" exists as a cheaper first step: it
  // takes no spot, needs no approval, and gives the host a reason to believe
  // someone will turn up.

  /// Social proof for a page of hangouts in ONE round trip, keyed by table id.
  /// Returns an empty map on failure — callers fall back to
  /// [HangoutSocialProof.unknown], which renders as empty rather than blank.
  Future<Map<String, HangoutSocialProof>> getSocialProof(
    List<String> tableIds,
  ) async {
    final ids = tableIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final res = await SupabaseConfig.client
          .rpc('get_hangout_social_proof', params: {'p_table_ids': ids});
      final map = Map<String, dynamic>.from(res as Map);
      return map.map(
        (k, v) => MapEntry(
          k,
          HangoutSocialProof.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error fetching hangout social proof: $e');
      return {};
    }
  }

  Future<HangoutSocialProof?> getSocialProofFor(String tableId) async {
    final all = await getSocialProof([tableId]);
    return all[tableId];
  }

  /// Marks the current user interested. Idempotent.
  Future<Map<String, dynamic>> markInterested(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Please sign in first'};
      }

      final table = await SupabaseConfig.client
          .from('tables')
          .select('host_id, title, status')
          .eq('id', tableId)
          .maybeSingle();
      if (table == null) {
        return {'success': false, 'message': 'This hangout no longer exists'};
      }
      if (table['host_id'] == user.id) {
        return {'success': false, 'message': "It's your own hangout"};
      }
      if (table['status'] != 'open') {
        return {'success': false, 'message': 'This hangout is closed'};
      }

      // Never downgrade someone who already holds a spot or has a request in.
      final existing = await SupabaseConfig.client
          .from('table_members')
          .select('status')
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) {
        final status = existing['status'] as String?;
        if (status == 'interested') {
          return {'success': true, 'message': null};
        }
        if (status == 'approved' ||
            status == 'joined' ||
            status == 'attended' ||
            status == 'pending') {
          return {'success': false, 'message': "You're already on the list"};
        }
      }

      await SupabaseConfig.client.from('table_members').upsert({
        'table_id': tableId,
        'user_id': user.id,
        'role': 'member',
        'status': 'interested',
        'requested_at': DateTime.now().toIso8601String(),
        'joined_at': null,
        'left_at': null,
      }, onConflict: 'table_id,user_id');

      // Tell the host. This is the entire point of the signal — a host does not
      // reopen their own hangout to check, so it has to reach them. Best-effort:
      // the interest itself is already recorded.
      try {
        final userName = await _getUserDisplayName(user.id);
        await SupabaseConfig.client.from('notifications').insert({
          'user_id': table['host_id'],
          'actor_id': user.id,
          'type': 'hangout_interest',
          'entity_id': tableId,
          'title': '$userName is interested',
          'body': table['title'] ?? 'Your hangout',
          'metadata': {'table_id': tableId},
        });
      } catch (e) {
        debugPrint('⚠️ Could not notify host of interest: $e');
      }

      return {'success': true, 'message': null};
    } catch (e) {
      debugPrint('⚠️ Error marking interested: $e');
      return {'success': false, 'message': 'Could not save that. Try again.'};
    }
  }

  /// Undoes [markInterested]. Only ever removes an 'interested' row, so it can
  /// never be used to drop a real membership.
  Future<bool> removeInterest(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return false;
      await SupabaseConfig.client
          .from('table_members')
          .delete()
          .eq('table_id', tableId)
          .eq('user_id', user.id)
          .eq('status', 'interested');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error removing interest: $e');
      return false;
    }
  }

  /// The interested list, for the host. Separate from [getTableMembers] because
  /// these people are NOT members and must never appear as guests.
  Future<List<Map<String, dynamic>>> getInterestedUsers(String tableId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('table_members')
          .select(
            'user_id, requested_at, '
            'users:user_id ( id, display_name, avatar_url, '
            'user_photos ( photo_url, is_primary ) )',
          )
          .eq('table_id', tableId)
          .eq('status', 'interested')
          .order('requested_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('⚠️ Error getting interested users: $e');
      return [];
    }
  }

  // ───────────────────────── Invites ─────────────────────────
  //
  // `invited` has been a legal `member_status_type` all along but nothing in
  // the app read it, so an invite could be written and the recipient had no
  // way to see or accept it. These three methods are that missing half.
  //
  // An invite holds NO spot: every capacity and roster query filters on
  // ('approved','joined','attended'), so inviting ten people to a four-seat
  // hangout does not fill it. Accepting runs the real [joinTable] path, which
  // is where capacity, approval and distance are actually enforced.

  /// Upcoming hangouts this user has been invited to but not yet answered.
  Future<List<Map<String, dynamic>>> getMyInvites() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return [];
    try {
      // Both statuses an invite can have. 'invited' is what every route now
      // writes; 'pending' is ambiguous — it means EITHER "I asked to join and
      // the host hasn't answered" OR "the host invited me when they created
      // this". Those cannot be told apart from the status alone, which is
      // exactly why `tables.invited_user_ids` exists, so a 'pending' row only
      // counts as an invite when this user is named in that array.
      final rows = await SupabaseConfig.client
          .from('table_members')
          .select('table_id, status, requested_at, tables ( * )')
          .eq('user_id', user.id)
          .inFilter('status', openInviteStatuses)
          .order('requested_at', ascending: false);

      final now = DateTime.now();

      final out = <Map<String, dynamic>>[];
      for (final row in rows) {
        final table = row['tables'];
        if (table == null) continue;
        final t = Map<String, dynamic>.from(table as Map);

        final ids = t['invited_user_ids'];
        if (!isOpenInvite(
          status: row['status']?.toString(),
          namedInInvitedArray: ids is List && ids.contains(user.id),
        )) {
          continue;
        }
        if (!isLiveInvite(
          hangoutStatus: t['status']?.toString(),
          startsAt: DateTime.tryParse(t['datetime']?.toString() ?? ''),
          now: now,
        )) {
          continue;
        }
        t['invited_at'] = row['requested_at'];
        out.add(t);
      }
      out.sort(
        (a, b) => DateTime.parse(
          a['datetime'],
        ).compareTo(DateTime.parse(b['datetime'])),
      );
      return out;
    } catch (e) {
      debugPrint('⚠️ Error getting invites: $e');
      return [];
    }
  }

  /// Count only — for a badge on the Hangouts tab.
  Future<int> getMyInviteCount() async => (await getMyInvites()).length;
}
