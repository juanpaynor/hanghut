import 'package:supabase_flutter/supabase_flutter.dart';

class StoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch recent stories for the "Friends' Moments" tray.
  /// Groups by USER (not location) so each person appears as one card.
  /// When [followingOnly] is true, only returns stories from users the current user follows.
  Future<List<Map<String, dynamic>>> getFriendsStories({
    bool followingOnly = false,
    int limit = 20,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      // Build the base query - fetch individual story posts from last 24h
      final selectCols = 'id, user_id, image_url, video_url, created_at, latitude, longitude, event_id, table_id, external_place_id, external_place_name, user:user_id(display_name, user_photos(photo_url, is_primary))';
      final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      List<dynamic> response;

      if (followingOnly) {
        final followingRows = await _supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', currentUserId);
        final followingIds = followingRows.map((row) => row['following_id'] as String).toList();
        if (followingIds.isEmpty) return [];
        response = await _supabase
            .from('posts')
            .select(selectCols)
            .eq('is_story', true)
            .gte('created_at', cutoff)
            .inFilter('user_id', followingIds)
            .order('created_at', ascending: false)
            .limit(100);
      } else {
        response = await _supabase
            .from('posts')
            .select(selectCols)
            .eq('is_story', true)
            .gte('created_at', cutoff)
            .order('created_at', ascending: false)
            .limit(100);
      }
      final rows = List<Map<String, dynamic>>.from(response);

      // Group by user_id
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final row in rows) {
        final userId = row['user_id'] as String;
        grouped.putIfAbsent(userId, () => []);
        grouped[userId]!.add(row);
      }

      // Build one tray card per user using their most recent story
      final List<Map<String, dynamic>> result = [];
      for (final entry in grouped.entries) {
        final stories = entry.value;
        final latest = stories.first; // Already ordered by created_at DESC
        final profile = latest['user'] as Map<String, dynamic>? ?? {};

        // Get photo from user_photos (primary first)
        String? photoUrl;
        final userPhotos = profile['user_photos'] as List?;
        if (userPhotos != null && userPhotos.isNotEmpty) {
          final primary = userPhotos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => userPhotos.first,
          );
          photoUrl = primary['photo_url'] as String?;
        }

        result.add({
          'author_id': entry.key,
          'author_name': profile['display_name'] ?? 'Friend',
          'author_avatar_url': photoUrl,
          'image_url': latest['image_url'],
          'video_url': latest['video_url'],
          'story_count': stories.length,
          'latest_story_time': latest['created_at'],
          // Pass location info from latest story for the viewer
          'event_id': latest['event_id'],
          'table_id': latest['table_id'],
          'external_place_id': latest['external_place_id'],
          'external_place_name': latest['external_place_name'],
          'latitude': latest['latitude'],
          'longitude': latest['longitude'],
        });
      }

      // Sort by most recent first & limit
      result.sort((a, b) => (b['latest_story_time'] ?? '').compareTo(a['latest_story_time'] ?? ''));
      return result.take(limit).toList();
    } catch (e) {
      print('❌ Error fetching friends stories: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStoriesInViewport({
    required double? minLat,
    required double? maxLat,
    required double? minLng,
    required double? maxLng,
  }) async {
    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return [];
    }

    try {
      final response = await _supabase
          .from('map_live_stories_view')
          .select()
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLng)
          .lte('longitude', maxLng)
          .limit(100);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching map stories: $e');
      return [];
    }
  }
}
