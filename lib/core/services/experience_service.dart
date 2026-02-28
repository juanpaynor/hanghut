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
}
