import 'package:bitemates/core/config/supabase_config.dart';

class ExperienceService {
  final _client = SupabaseConfig.client;

  /// Fetch full details for an experience (Table) including Host profile
  Future<Map<String, dynamic>> getExperienceDetails(String tableId) async {
    try {
      // Fetch table + host info
      // We can use the 'map_ready_tables' view if it contains everything,
      // or join 'tables' with 'users'.
      // map_ready_tables is good because it pre-calculates stuff.
      final response = await _client
          .from('map_ready_tables')
          .select()
          .eq('id', tableId)
          .single();

      return response;
    } catch (e) {
      print('❌ Error fetching experience details: $e');
      rethrow;
    }
  }

  /// Fetch upcoming schedules for an experience
  Future<List<Map<String, dynamic>>> getSchedules(String tableId) async {
    try {
      final response = await _client
          .from('experience_schedules')
          .select()
          .eq('table_id', tableId)
          .gte(
            'end_time',
            DateTime.now().toIso8601String(),
          ) // Only future/ongoing
          .order('start_time', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching schedules: $e');
      return [];
    }
  }

  /// Create a purchase intent for a booking
  Future<Map<String, dynamic>> createPaymentIntent({
    required String tableId,
    required String scheduleId,
    required int quantity,
    required Map<String, String> guestDetails,
    bool subscribedToNewsletter = true,
  }) async {
    try {
      final user = _client.auth.currentUser;

      final response = await _client.functions.invoke(
        'create-experience-intent',
        body: {
          'table_id': tableId,
          'schedule_id': scheduleId,
          'quantity': quantity,
          'guest_details': guestDetails, // {name, email, phone}
          'success_url': 'https://hanghut.com/checkout/success',
          'failure_url': 'https://hanghut.com/experiences/$tableId',
          'subscribed_to_newsletter': subscribedToNewsletter,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to create intent: ${response.status}');
      }

      final data = response.data;
      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      return data['data']; // {intent_id, payment_url}
    } catch (e) {
      print('❌ Error creating payment intent: $e');
      rethrow;
    }
  }

  /// Fetch current user's experience bookings
  Future<List<Map<String, dynamic>>> getMyBookings() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('experience_purchase_intents')
          .select('''
            *,
            table:tables (
              id,
              title,
              venue_name:location_name,
              cover_image_url:image_url,
              host_id
            ),
            schedule:experience_schedules!schedule_id (
              start_time,
              end_time
            )
          ''')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      final bookings = List<Map<String, dynamic>>.from(response);

      // Resolve host info for each booking
      final hostIds = bookings
          .map((b) => (b['table'] as Map?)?['host_id'] as String?)
          .where((id) => id != null)
          .toSet();

      if (hostIds.isNotEmpty) {
        final hosts = await _client
            .from('users')
            .select('id, display_name, avatar_url')
            .inFilter('id', hostIds.toList());

        final hostMap = <String, dynamic>{
          for (final h in List<Map<String, dynamic>>.from(hosts))
            h['id'] as String: h,
        };

        for (final booking in bookings) {
          final table = booking['table'] as Map<String, dynamic>?;
          if (table != null && table['host_id'] != null) {
            table['host'] = hostMap[table['host_id']];
          }
        }
      }

      return bookings;
    } catch (e) {
      print('❌ Error fetching experience bookings: $e');
      return [];
    }
  }

  // =====================
  // Reviews & Ratings
  // =====================

  /// Check if current user has a completed booking for this experience
  Future<bool> hasCompletedBooking(String experienceId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final result = await _client
          .from('experience_purchase_intents')
          .select('id')
          .eq('table_id', experienceId)
          .eq('user_id', userId)
          .eq('status', 'completed')
          .limit(1);

      return (result as List).isNotEmpty;
    } catch (e) {
      print('❌ Error checking booking: $e');
      return false;
    }
  }

  /// Submit or update a review for an experience
  Future<void> submitReview({
    required String experienceId,
    required int rating,
    String? reviewText,
    int? communicationRating,
    int? valueRating,
    int? organizationRating,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    try {
      await _client.from('experience_reviews').upsert(
        {
          'experience_id': experienceId,
          'user_id': userId,
          'rating': rating,
          'review_text': reviewText,
          'communication_rating': communicationRating,
          'value_rating': valueRating,
          'organization_rating': organizationRating,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'experience_id,user_id',
      );
    } catch (e) {
      print('❌ Error submitting review: $e');
      rethrow;
    }
  }

  /// Get all reviews for an experience, with reviewer info
  Future<List<Map<String, dynamic>>> getReviews(String experienceId) async {
    try {
      final reviews = await _client
          .from('experience_reviews')
          .select('*, user:users!user_id(id, display_name)')
          .eq('experience_id', experienceId)
          .order('created_at', ascending: false);

      final reviewList = List<Map<String, dynamic>>.from(reviews);

      // Fetch reviewer photos
      final userIds = reviewList
          .map((r) {
            final user = r['user'];
            if (user is Map) return user['id'] as String?;
            return null;
          })
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();

      if (userIds.isNotEmpty) {
        final photos = await _client
            .from('user_photos')
            .select('user_id, photo_url')
            .inFilter('user_id', userIds)
            .eq('is_primary', true);

        final photoMap = {
          for (var p in photos) p['user_id']: p['photo_url'],
        };

        for (var review in reviewList) {
          final user = review['user'];
          if (user is Map && user['id'] != null) {
            review['user_photo'] = photoMap[user['id']];
          }
        }
      }

      return reviewList;
    } catch (e) {
      print('❌ Error fetching reviews: $e');
      return [];
    }
  }

  /// Get average rating and category averages for an experience
  Future<Map<String, dynamic>> getAverageRating(String experienceId) async {
    try {
      final reviews = await _client
          .from('experience_reviews')
          .select('rating, communication_rating, value_rating, organization_rating')
          .eq('experience_id', experienceId);

      final list = List<Map<String, dynamic>>.from(reviews);

      if (list.isEmpty) {
        return {
          'average': 0.0,
          'count': 0,
          'communication': 0.0,
          'value': 0.0,
          'organization': 0.0,
        };
      }

      double avg(String key) {
        final vals = list
            .map((r) => r[key] as int?)
            .where((v) => v != null)
            .cast<int>()
            .toList();
        if (vals.isEmpty) return 0.0;
        return vals.reduce((a, b) => a + b) / vals.length;
      }

      return {
        'average': avg('rating'),
        'count': list.length,
        'communication': avg('communication_rating'),
        'value': avg('value_rating'),
        'organization': avg('organization_rating'),
      };
    } catch (e) {
      print('❌ Error fetching average rating: $e');
      return {'average': 0.0, 'count': 0, 'communication': 0.0, 'value': 0.0, 'organization': 0.0};
    }
  }
}
