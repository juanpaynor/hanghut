import 'package:supabase_flutter/supabase_flutter.dart';

class StoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
