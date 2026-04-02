import 'package:supabase_flutter/supabase_flutter.dart';

class StoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch story tray using server-side RPC with closeness ranking,
  /// seen/unseen state, and pagination.
  /// Returns one entry per author, sorted: own → unseen (by closeness) → seen.
  Future<List<Map<String, dynamic>>> getFriendsStories({
    bool followingOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase.rpc(
        'get_story_tray',
        params: {
          'p_following_only': followingOnly,
          'p_limit': limit,
          'p_offset': offset,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching story tray: $e');
      return [];
    }
  }

  /// Mark a user's stories as viewed.
  /// Called when the user finishes viewing someone's stories.
  Future<void> markStoriesViewed(String authorId) async {
    try {
      await _supabase.rpc(
        'mark_stories_viewed',
        params: {'p_author_id': authorId},
      );
    } catch (e) {
      print('❌ Error marking stories viewed: $e');
    }
  }

  /// Fetch all individual stories for a specific user (for the story viewer).
  Future<List<Map<String, dynamic>>> getUserStories(String userId) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
      final response = await _supabase
          .from('posts')
          .select('id, user_id, image_url, video_url, created_at, latitude, longitude, event_id, table_id, external_place_id, external_place_name, content')
          .eq('is_story', true)
          .eq('user_id', userId)
          .gte('created_at', cutoff)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching user stories: $e');
      return [];
    }
  }

  /// Fetch stories in a map viewport using PostGIS RPC.
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
      // Use PostGIS-powered RPC (ST_Intersects on GiST index)
      final response = await _supabase.rpc(
        'get_stories_in_viewport',
        params: {
          'min_lat': minLat,
          'max_lat': maxLat,
          'min_lng': minLng,
          'max_lng': maxLng,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching map stories: $e');
      return [];
    }
  }
}
