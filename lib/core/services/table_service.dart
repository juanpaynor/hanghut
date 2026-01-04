import 'dart:math';
import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/social_service.dart';

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
      var query = SupabaseConfig.client.from('map_ready_tables').select();

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

      // Order by scheduled time to get soonest events first, but limiting is key.
      var builder = query.order('scheduled_time', ascending: true);

      // Apply limit if provided
      if (limit != null) {
        builder = builder.limit(limit);
      }

      final response = await builder;

      // final response = await SupabaseConfig.client
      //     .from('map_ready_tables')
      //     .select()
      //     .order('scheduled_time', ascending: true);

      final tables = List<Map<String, dynamic>>.from(response);

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
    String? description, // NEW parameter
    required int maxCapacity,
    required int budgetMin,
    required int budgetMax,
    required bool requiresApproval,
    required String goalType,
    File? markerImage,
    String? markerEmoji,
    String? imageUrl,
  }) async {
    print('📊 TABLE SERVICE: createTable called');
    print('  - Venue: $venueName');
    print('  - Description: ${description ?? "None"}');

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final insertData = {
        'host_id': user.id,
        'title': title ?? venueName,
        'latitude': latitude,
        'longitude': longitude,
        'datetime': scheduledTime.toIso8601String(),
        'location_name': venueName,
        'venue_address': venueAddress,
        'description': description, // Pass description to DB
        'max_guests': maxCapacity,
        'cuisine_type': activityType,
        'price_per_person': budgetMax,
        'status': 'open',
        'chat_storage_type':
            'telegram', // New tables use Telegram local-first mode
        if (markerEmoji != null) 'marker_emoji': markerEmoji,
        if (imageUrl != null) 'image_url': imageUrl,
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

      // Auto-Post to Feed (New Feature)
      try {
        print('📣 TABLE SERVICE: Auto-posting to feed...');

        await SocialService().createSystemPost(
          content: 'New Hangout: $venueName',
          postType: 'hangout',
          visibility: 'public',
          latitude: latitude,
          longitude: longitude,
          metadata: {
            'table_id': tableId,
            'venue_name': venueName,
            'venue_address': venueAddress,
            'scheduled_time': scheduledTime.toIso8601String(),
            'activity_type': activityType,
            'description': description, // Pass to Feed Metadata
            'image_url': markerImageUrl ?? imageUrl,
            'marker_emoji': markerEmoji,
            'max_capacity': maxCapacity,
          },
        );
        print('✅ TABLE SERVICE: Auto-post successful');
      } catch (e) {
        print('⚠️ TABLE SERVICE: Failed to auto-post: $e');
      }

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

      // 3. Mark associated Feed Post as ENDED (instead of deleting it?)
      // We search for a post where metadata->>table_id matches
      final postResponse = await SupabaseConfig.client
          .from('posts')
          .select('id, metadata')
          .eq('post_type', 'hangout')
          // Using a filter on jsonb column
          // Note: .filter('metadata->>table_id', 'eq', tableId)
          .filter('metadata->>table_id', 'eq', tableId)
          .maybeSingle();

      if (postResponse != null) {
        final postId = postResponse['id'];
        final metadata = postResponse['metadata'] as Map<String, dynamic>;

        print('🔄 TABLE SERVICE: Updating associated feed post $postId');

        // Update status in metadata
        metadata['status'] = 'ended';

        await SupabaseConfig.client
            .from('posts')
            .update({'metadata': metadata})
            .eq('id', postId);

        // Notify Ably about the update (using 'post_updated' event if we had one,
        // but for now the client might just see it on refresh.
        // Ideally we'd emit an event. Let's assume AblyService handles this if we add it.)
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
