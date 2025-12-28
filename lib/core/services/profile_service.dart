import 'package:bitemates/core/config/supabase_config.dart';

class ProfileService {
  // Fetch available interest tags
  Future<List<Map<String, dynamic>>> getInterestTags() async {
    try {
      final response = await SupabaseConfig.client
          .from('interest_tags')
          .select('id, name, category, icon');

      final tags = List<Map<String, dynamic>>.from(response);
      print('Fetched ${tags.length} interest tags');
      return tags;
    } catch (e) {
      print('Error fetching interest tags: $e');
      rethrow;
    }
  }

  // Save full profile
  Future<void> createProfile({
    required String userId,
    required String bio,
    required DateTime dob,
    required String gender,
    required Map<String, int> personality,
    required List<String> interestTagIds,
    required Map<String, dynamic> preferences,
    String? photoUrl,
  }) async {
    // Get user email from Supabase auth
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw Exception('No authenticated user');

    try {
      // 1. Insert or Update User in public.users table
      await SupabaseConfig.client.from('users').upsert({
        'id': userId,
        'email': user.email,
        'display_name': user.userMetadata?['display_name'],
        'bio': bio,
        'date_of_birth': dob.toIso8601String().split('T')[0],
        'gender_identity': gender,
      });

      // 2. Insert Personality
      await SupabaseConfig.client.from('user_personality').upsert({
        'user_id': userId,
        ...personality,
      });

      // 3. Insert Preferences
      await SupabaseConfig.client.from('user_preferences').upsert({
        'user_id': userId,
        ...preferences,
      });

      // 4. Insert Interests
      if (interestTagIds.isNotEmpty) {
        final interestsObjects = interestTagIds
            .map((tagId) => {'user_id': userId, 'interest_tag_id': tagId})
            .toList();

        await SupabaseConfig.client
            .from('user_interests')
            .insert(interestsObjects);
      }

      // 5. Insert Photo if provided
      if (photoUrl != null) {
        await SupabaseConfig.client.from('user_photos').insert({
          'user_id': userId,
          'photo_url': photoUrl,
          'is_primary': true,
          'display_order': 0,
        });
      }
    } catch (e) {
      print('Error creating profile: $e');
      rethrow;
    }
  }
}
