import 'dart:math';
import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/friends_going_service.dart';
import 'package:bitemates/core/constants/model_registry.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';

class TableService {
  // Fetch active tables from map_ready_tables view
  Future<List<Map<String, dynamic>>> getMapReadyTables({
    double? userLat,
    double? userLng,
    double? radiusKm,
    // New: Bounding box for viewport filtering
    double? minLat,
    double? maxLat,
    double? minLng,
    double? maxLng,
    int? limit, // New: Server-side limit
  }) async {
    try {
      var query = SupabaseConfig.client.from('map_ready_tables').select('''
        id, title, location_lat, location_lng, venue_name, venue_address,
        scheduled_time, max_capacity, status, current_capacity,
        marker_image_url, marker_emoji, image_url, images,
        activity_type, price_per_person, visibility,
        experience_type, video_url, currency, is_experience,
        verified_by_hanghut, host_id, host_name, host_photo_url,
        host_trust_score, member_count, seats_left, availability_state
      ''');

      // Apply server-side bounding box filter if active
      if (minLat != null &&
          maxLat != null &&
          minLng != null &&
          maxLng != null) {
        query = query
            .gte('location_lat', minLat)
            .lte('location_lat', maxLat)
            .gte('location_lng', minLng)
            .lte('location_lng', maxLng);
      }

      // Exclude group-only activities from public map
      query = query.neq('visibility', 'group_only');

      // Order by scheduled time to get soonest events first, but limiting is key.
      var builder = query.order('scheduled_time', ascending: true);

      // Apply limit if provided
      if (limit != null) {
        builder = builder.limit(limit);
      }

      final response = await builder;

      final tables = List<Map<String, dynamic>>.from(response);
      // ✅ No enrichment query needed — view now includes
      // marker_image_url, marker_emoji, image_url, images

      // Optional: filter by distance client-side if provided (and bounds not used, or as extra check)
      if (userLat != null && userLng != null && radiusKm != null) {
        return tables.where((table) {
          final distance = _calculateDistance(
            userLat,
            userLng,
            table['location_lat'],
            table['location_lng'],
          );
          return distance <= radiusKm;
        }).toList();
      }

      return tables;
    } catch (e) {
      print('Error fetching tables: $e');
      rethrow;
    }
  }

  // Fetch experiences specifically for the new carousel
  Future<List<Map<String, dynamic>>> getExperiences({
    double? userLat,
    double? userLng,
    int limit = 10,
  }) async {
    try {
      final response = await SupabaseConfig.client
          .from('map_ready_tables')
          .select()
          .eq('is_experience', true) // Filter by the actual experience flag
          .eq('verified_by_hanghut', true) // Only show approved experiences
          .order('scheduled_time', ascending: true)
          .limit(limit);

      final tables = List<Map<String, dynamic>>.from(response);
      // ✅ No enrichment query needed — view now includes
      // marker_image_url, marker_emoji, image_url, images

      return tables;
    } catch (e) {
      print('Error fetching experiences: $e');
      return [];
    }
  }

  // Haversine formula for distance calculation
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371; // Earth's radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Enrich tables with member avatar URLs and friends-here data
  /// for the Open Hangouts carousel cards.
  Future<List<Map<String, dynamic>>> enrichTablesWithMembers(
    List<Map<String, dynamic>> tables,
  ) async {
    if (tables.isEmpty) return tables;

    try {
      final tableIds = tables.map((t) => t['id'] as String).toList();

      // 1. Batch-fetch first 5 members (with avatars) for all tables
      final membersResp = await SupabaseConfig.client
          .from('table_members')
          .select('''
            table_id,
            user_id,
            users:user_id (
              id,
              display_name,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .inFilter('table_id', tableIds)
          .inFilter('status', ['approved', 'joined', 'attended'])
          .order('joined_at', ascending: true);

      // Group members by table_id
      final membersByTable = <String, List<Map<String, dynamic>>>{};
      for (final m in (membersResp as List)) {
        final tId = m['table_id'] as String;
        membersByTable.putIfAbsent(tId, () => []);
        if ((membersByTable[tId]?.length ?? 0) < 5) {
          membersByTable[tId]!.add(Map<String, dynamic>.from(m));
        }
      }

      // 2. Fetch friends-at-table for the current user
      final friendsService = FriendsGoingService();
      final friendsByTable = <String, List<Map<String, dynamic>>>{};
      // Only fetch for tables that actually have members (avoid empty RPC calls)
      for (final tId in tableIds) {
        try {
          final friends = await friendsService.getFriendsAtTable(tId);
          if (friends.isNotEmpty) {
            friendsByTable[tId] = friends;
          }
        } catch (_) {
          // Non-critical — skip if RPC fails for one table
        }
      }

      // 3. Attach data to each table map
      for (final table in tables) {
        final tId = table['id'] as String;

        // Extract avatar URLs from members
        final members = membersByTable[tId] ?? [];
        final avatarUrls = <String>[];
        for (final member in members) {
          final user = member['users'];
          if (user != null && user is Map) {
            final photos = user['user_photos'];
            if (photos != null && photos is List && photos.isNotEmpty) {
              // Primary photo first, fallback to first
              final primary = photos.firstWhere(
                (p) => p['is_primary'] == true,
                orElse: () => photos.first,
              );
              if (primary['photo_url'] != null) {
                avatarUrls.add(primary['photo_url'] as String);
              }
            }
          }
        }

        table['member_avatars'] = avatarUrls;
        table['member_avatar_count'] = members.length;

        // Friends data
        final friends = friendsByTable[tId] ?? [];
        table['friends_here'] = friends;
      }

      return tables;
    } catch (e) {
      print('TableService: Error enriching tables with members: $e');
      // Return tables as-is if enrichment fails
      return tables;
    }
  }

  // Upload marker image to Supabase Storage
  Future<String?> _uploadMarkerImage(String tableId, File imageFile) async {
    try {
      print('📸 TABLE SERVICE: Uploading marker image...');
      print('  - File path: ${imageFile.path}');
      print('  - Table ID: $tableId');

      final fileExt = imageFile.path.split('.').last;
      final fileName = '$tableId.$fileExt';
      final filePath = '$fileName'; // Remove 'markers/' prefix

      print('  - Storage path: $filePath');

      await SupabaseConfig.client.storage
          .from('table-markers')
          .upload(filePath, imageFile);

      final publicUrl = SupabaseConfig.client.storage
          .from('table-markers')
          .getPublicUrl(filePath);

      print('✅ TABLE SERVICE: Image uploaded successfully');
      print('  - Public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('❌ TABLE SERVICE: Error uploading image - $e');
      print('  - Error type: ${e.runtimeType}');
      return null;
    }
  }

  // Delete marker image from Supabase Storage
  Future<void> deleteMarkerImage(String? markerImageUrl) async {
    if (markerImageUrl == null) return;

    try {
      // Extract file path from URL
      final uri = Uri.parse(markerImageUrl);
      final fileName = uri.pathSegments.last;

      await SupabaseConfig.client.storage.from('table-markers').remove([
        fileName,
      ]);

      print('✅ TABLE SERVICE: Marker image deleted');
    } catch (e) {
      print('❌ TABLE SERVICE: Error deleting image - $e');
    }
  }

  // Create a new table
  Future<String> createTable({
    required double latitude,
    required double longitude,
    required DateTime scheduledTime,
    required String activityType,
    required String venueName,
    required String venueAddress,
    String? title,
    String? description,
    required int maxCapacity,
    required int budgetMin,
    required int budgetMax,
    required bool requiresApproval,
    required String goalType,
    File? markerImage,
    String? markerEmoji,
    String? imageUrl,
    String visibility = 'public',
    Map<String, dynamic>? filters,
    List<String>? invitedUserIds,
    String? groupId, // Group-hosted activity
  }) async {
    print('📊 TABLE SERVICE: createTable called');
    print('  - Venue: $venueName');
    print('  - Description: ${description ?? "None"}');

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Detect 3D Model logic (Store-on-Write)
      // We check title, description, and cuisineType for keywords
      final textToScan = '${title ?? ''} ${description ?? ''} $activityType';
      final markerModelPath = ModelRegistry.detectActivityModel(textToScan);

      final insertData = {
        'host_id': user.id,
        'title': title ?? venueName,
        'latitude': latitude,
        'longitude': longitude,
        'datetime': scheduledTime.toIso8601String(),
        'location_name': venueName,
        'venue_address': venueAddress,
        'description': description,
        'max_guests': maxCapacity,
        'cuisine_type': activityType,
        'price_per_person': budgetMax,
        'status': 'open',
        'requires_approval': requiresApproval,
        'visibility': visibility,
        'chat_storage_type':
            'telegram', // New tables use Telegram local-first mode
        'marker_model': markerModelPath,
        if (markerEmoji != null) 'marker_emoji': markerEmoji,
        if (imageUrl != null) 'image_url': imageUrl,
        if (filters != null && filters.isNotEmpty) 'filters': filters,
        if (invitedUserIds != null && invitedUserIds.isNotEmpty)
          'invited_user_ids': invitedUserIds,
        if (groupId != null) 'group_id': groupId,
      };

      print('📤 TABLE SERVICE: Sending to Supabase...');
      print('  Data: $insertData');

      final response = await SupabaseConfig.client
          .from('tables')
          .insert(insertData)
          .select('id')
          .single();

      final tableId = response['id'] as String;
      print('✅ TABLE SERVICE: Insert successful!');
      print('  - Table ID: $tableId');

      // Upload marker image if provided
      String? markerImageUrl;
      if (markerImage != null) {
        print('📸 TABLE SERVICE: Processing marker image upload...');
        markerImageUrl = await _uploadMarkerImage(tableId, markerImage);
        if (markerImageUrl != null) {
          print(
            '📝 TABLE SERVICE: Updating table with marker URL: $markerImageUrl',
          );
          // Update table with image URL
          await SupabaseConfig.client
              .from('tables')
              .update({'marker_image_url': markerImageUrl})
              .eq('id', tableId);
          print('✅ TABLE SERVICE: Table updated with marker image URL');
        } else {
          print(
            '⚠️ TABLE SERVICE: Image upload returned null, marker_image_url not set',
          );
        }
      } else {
        print('ℹ️ TABLE SERVICE: No marker image provided');
      }

      // 4. Add Host as a Member (Critical for Chat/List visibility)
      try {
        print('👤 TABLE SERVICE: Adding host to table_members...');
        await SupabaseConfig.client.from('table_members').insert({
          'table_id': tableId,
          'user_id': user.id,
          'role': 'host',
          'status': 'approved', // Using 'approved' to match list filter
          'requested_at': DateTime.now().toIso8601String(),
          'approved_at': DateTime.now().toIso8601String(),
          'joined_at': DateTime.now().toIso8601String(),
        });
        print('✅ TABLE SERVICE: Host added as member');
      } catch (e) {
        print('⚠️ TABLE SERVICE: Failed to add host as member: $e');
      }

      // Auto-add invited users as pending table members
      if (invitedUserIds != null && invitedUserIds.isNotEmpty) {
        try {
          print(
            '📨 TABLE SERVICE: Adding ${invitedUserIds.length} invited users...',
          );
          final inviteRows = invitedUserIds
              .map(
                (uid) => {
                  'table_id': tableId,
                  'user_id': uid,
                  'role': 'member',
                  'status': 'pending',
                  'requested_at': DateTime.now().toIso8601String(),
                },
              )
              .toList();
          await SupabaseConfig.client.from('table_members').insert(inviteRows);
          print('✅ TABLE SERVICE: Invited users added');
        } catch (e) {
          print('⚠️ TABLE SERVICE: Failed to add invited users: $e');
        }
      }

      // Auto-Post to Feed (skip for mystery and group_only tables — they should stay hidden)
      if (visibility != 'mystery' && visibility != 'group_only') {
        try {
          print('📣 TABLE SERVICE: Auto-posting to feed...');

          await SocialService().createSystemPost(
            content: 'New Hangout: $venueName',
            postType: 'hangout',
            visibility: visibility == 'followers_only' ? 'followers' : 'public',
            latitude: latitude,
            longitude: longitude,
            metadata: {
              'table_id': tableId,
              'venue_name': venueName,
              'venue_address': venueAddress,
              'scheduled_time': scheduledTime.toIso8601String(),
              'activity_type': activityType,
              'title': title ?? venueName,
              'description': description,
              'image_url': markerImageUrl ?? imageUrl,
              'marker_emoji': markerEmoji,
              'max_capacity': maxCapacity,
              if (filters != null && filters.isNotEmpty) 'filters': filters,
              'visibility': visibility,
            },
          );
          print('✅ TABLE SERVICE: Auto-post successful');
        } catch (e) {
          print('⚠️ TABLE SERVICE: Failed to auto-post: $e');
        }
      } else {
        print('🔮 TABLE SERVICE: Skipping feed post for mystery table');
      }

      // ═══ INVITE NOTIFICATIONS (in-app + push) ═══
      if (invitedUserIds != null && invitedUserIds.isNotEmpty) {
        try {
          final hostName = user.userMetadata?['display_name'] ?? 'Someone';
          final tableTitle = title ?? venueName;
          print(
            '🔔 TABLE SERVICE: Sending invite notifications to ${invitedUserIds.length} users...',
          );

          for (final inviteeId in invitedUserIds) {
            // 1. In-app notification (bell)
            try {
              await SupabaseConfig.client.from('notifications').insert({
                'user_id': inviteeId,
                'actor_id': user.id,
                'type': 'hangout_invite',
                'title': 'You\'re Invited! 🎉',
                'body': '$hostName invited you to "$tableTitle"',
                'entity_id': tableId,
                'metadata': {'table_id': tableId},
              });
            } catch (e) {
              print(
                '⚠️ Failed to insert invite notification for $inviteeId: $e',
              );
            }

            // 2. Push notification
            try {
              await SupabaseConfig.client.functions.invoke(
                'send-push',
                body: {
                  'user_id': inviteeId,
                  'title': 'You\'re Invited! 🎉',
                  'body': '$hostName invited you to "$tableTitle"',
                  'data': {'type': 'table_join', 'table_id': tableId},
                },
              );
            } catch (e) {
              print('⚠️ Failed to send invite push for $inviteeId: $e');
            }
          }
          print('✅ TABLE SERVICE: Invite notifications sent');
        } catch (e) {
          print('⚠️ TABLE SERVICE: Failed to send invite notifications: $e');
        }
      }

      // ═══ FOLLOWER NOTIFICATIONS (in-app + push) — public only ═══
      if (visibility == 'public') {
        try {
          final hostName = user.userMetadata?['display_name'] ?? 'Someone';
          final tableTitle = title ?? venueName;
          print('🔔 TABLE SERVICE: Fetching followers for notification...');

          // Fetch up to 50 followers
          final followersResp = await SupabaseConfig.client
              .from('follows')
              .select('follower_id')
              .eq('following_id', user.id)
              .limit(50);

          final followerIds = (followersResp as List)
              .map((f) => f['follower_id'] as String)
              .where(
                (fid) =>
                    fid != user.id && !(invitedUserIds?.contains(fid) ?? false),
              ) // skip already-invited
              .toList();

          if (followerIds.isNotEmpty) {
            print(
              '🔔 TABLE SERVICE: Notifying ${followerIds.length} followers...',
            );

            // Batch insert in-app notifications
            try {
              final notifRows = followerIds
                  .map(
                    (fid) => {
                      'user_id': fid,
                      'actor_id': user.id,
                      'type': 'follower_hangout',
                      'title': 'New Hangout from $hostName 🔥',
                      'body':
                          '$hostName just created "$tableTitle" — join now!',
                      'entity_id': tableId,
                      'metadata': {'table_id': tableId},
                    },
                  )
                  .toList();
              await SupabaseConfig.client
                  .from('notifications')
                  .insert(notifRows);
            } catch (e) {
              print('⚠️ Failed to batch insert follower notifications: $e');
            }

            // Send push notifications (fire-and-forget, don't block creation)
            for (final fid in followerIds) {
              SupabaseConfig.client.functions
                  .invoke(
                    'send-push',
                    body: {
                      'user_id': fid,
                      'title': 'New Hangout from $hostName 🔥',
                      'body':
                          '$hostName just created "$tableTitle" — join now!',
                      'data': {'type': 'table_join', 'table_id': tableId},
                    },
                  )
                  .then((_) {})
                  .catchError((e) {
                    print('⚠️ Failed to send follower push for $fid: $e');
                  });
            }
            print('✅ TABLE SERVICE: Follower notifications sent');
          }
        } catch (e) {
          print('⚠️ TABLE SERVICE: Failed to send follower notifications: $e');
        }
      }
      // ═══ GROUP MEMBER NOTIFICATIONS (in-app + push) ═══
      if (groupId != null) {
        try {
          final hostName = user.userMetadata?['display_name'] ?? 'Someone';
          final tableTitle = title ?? venueName;
          print('🔔 TABLE SERVICE: Fetching group members for notification...');

          // Get group name
          String groupName = 'the group';
          try {
            final gResp = await SupabaseConfig.client
                .from('groups')
                .select('name')
                .eq('id', groupId)
                .single();
            groupName = gResp['name'] ?? 'the group';
          } catch (_) {}

          // Fetch all approved group members
          final membersResp = await SupabaseConfig.client
              .from('group_members')
              .select('user_id')
              .eq('group_id', groupId)
              .eq('status', 'approved');

          final memberIds = (membersResp as List)
              .map((m) => m['user_id'] as String)
              .where(
                (mid) =>
                    mid != user.id && // skip creator
                    !(invitedUserIds?.contains(mid) ?? false),
              ) // skip already-invited
              .toList();

          if (memberIds.isNotEmpty) {
            print(
              '🔔 TABLE SERVICE: Notifying ${memberIds.length} group members...',
            );

            // Batch insert in-app notifications
            try {
              final notifRows = memberIds
                  .map(
                    (mid) => {
                      'user_id': mid,
                      'actor_id': user.id,
                      'type': 'group_activity',
                      'title': 'New Activity in $groupName 🎯',
                      'body': '$hostName created "$tableTitle"',
                      'entity_id': tableId,
                      'metadata': {'table_id': tableId, 'group_id': groupId},
                    },
                  )
                  .toList();
              await SupabaseConfig.client
                  .from('notifications')
                  .insert(notifRows);
            } catch (e) {
              print('⚠️ Failed to batch insert group notifications: $e');
            }

            // Send push notifications (fire-and-forget)
            for (final mid in memberIds) {
              SupabaseConfig.client.functions
                  .invoke(
                    'send-push',
                    body: {
                      'user_id': mid,
                      'title': 'New Activity in $groupName 🎯',
                      'body': '$hostName created "$tableTitle"',
                      'data': {'type': 'table_join', 'table_id': tableId},
                    },
                  )
                  .then((_) {})
                  .catchError((e) {
                    print('⚠️ Failed to send group push for $mid: $e');
                  });
            }
            print('✅ TABLE SERVICE: Group member notifications sent');
          }
        } catch (e) {
          print('⚠️ TABLE SERVICE: Failed to send group notifications: $e');
        }
      }

      // Award XP for hosting an event
      BadgeService()
          .incrementStats(user.id, hosted: 1, baseXp: XpValues.hostEvent)
          .ignore();

      return tableId;
    } catch (e) {
      print('❌ TABLE SERVICE: Error creating table');
      print('  - Error: $e');
      print('  - Type: ${e.runtimeType}');
      rethrow;
    }
  }

  // Delete a table
  Future<void> deleteTable(String tableId) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('🗑️ TABLE SERVICE: Deleting table $tableId');

      // 1. Get table details first (for cleanup if needed)
      final table = await SupabaseConfig.client
          .from('tables')
          .select()
          .eq('id', tableId)
          .single();

      // 2. Delete the table (This will cascade to members, chat, etc. based on DB rules)
      await SupabaseConfig.client
          .from('tables')
          .delete()
          .eq('id', tableId)
          .eq('host_id', user.id); // Security: Ensure host owns it

      print('✅ TABLE SERVICE: Table deleted from DB');

      // 3. Delete associated Feed Post
      // We search for a post where metadata->>table_id matches
      final postResponse = await SupabaseConfig.client
          .from('posts')
          .select('id')
          .eq('post_type', 'hangout')
          .filter('metadata->>table_id', 'eq', tableId)
          .maybeSingle();

      if (postResponse != null) {
        final postId = postResponse['id'];
        print('🗑️ TABLE SERVICE: Deleting associated feed post $postId');

        await SupabaseConfig.client.from('posts').delete().eq('id', postId);

        print('✅ TABLE SERVICE: Feed post deleted');
      }

      // 4. Cleanup Marker Image
      if (table['marker_image_url'] != null) {
        await deleteMarkerImage(table['marker_image_url']);
      }
    } catch (e) {
      print('❌ TABLE SERVICE: Error deleting table - $e');
      rethrow;
    }
  }
}
