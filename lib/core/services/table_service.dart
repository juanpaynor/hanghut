import 'dart:math';
import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';

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
  }) async {
    try {
      var query = SupabaseConfig.client
          .from('map_ready_tables')
          .select();

      // Apply server-side bounding box filter if active
      if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
        query = query
            .gte('location_lat', minLat)
            .lte('location_lat', maxLat)
            .gte('location_lng', minLng)
            .lte('location_lng', maxLng);
      }
      
      final response = await query.order('scheduled_time', ascending: true);

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
    String? description,
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
    print('  - Location: ($latitude, $longitude)');
    print('  - Scheduled: ${scheduledTime.toIso8601String()}');
    print('  - Activity: $activityType, Capacity: $maxCapacity');
    print('  - Has marker image: ${markerImage != null}');
    print('  - Marker emoji: $markerEmoji');

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
        'description': description,
        'max_guests': maxCapacity,
        'cuisine_type': activityType,
        'price_per_person': budgetMax,
        'status': 'open',
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
      // Upload marker image if provided
      if (markerImage != null) {
        print('📸 TABLE SERVICE: Processing marker image upload...');
        final imageUrl = await _uploadMarkerImage(tableId, markerImage);
        if (imageUrl != null) {
          print('📝 TABLE SERVICE: Updating table with marker URL: $imageUrl');
          // Update table with image URL
          await SupabaseConfig.client
              .from('tables')
              .update({'marker_image_url': imageUrl})
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
      return tableId;
    } catch (e) {
      print('❌ TABLE SERVICE: Error creating table');
      print('  - Error: $e');
      print('  - Type: ${e.runtimeType}');
      rethrow;
    }
  }
}
