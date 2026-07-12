import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

class EventService {
  /// Fetch events within map viewport bounds
  Future<List<Event>> getEventsInViewport({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    try {
      final response = await SupabaseConfig.client.rpc(
        'get_events_in_viewport',
        params: {
          'min_lat': minLat,
          'max_lat': maxLat,
          'min_lng': minLng,
          'max_lng': maxLng,
        },
      );

      if (response == null) return [];

      final events = (response as List)
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();

      print('📅 Fetched ${events.length} events in viewport');
      return events;
    } catch (e) {
      print('❌ Error fetching events: $e');
      return [];
    }
  }

  /// Fetch upcoming events for Feed carousel / Discover.
  ///
  /// Optional [startDate]/[endDate] filter by `start_datetime` (inclusive of the
  /// whole end day — pass the day's 23:59:59). When [startDate] is omitted the
  /// lower bound defaults to now (only future events).
  ///
  /// Pagination: pass [offset] to fetch the next page ([limit] rows per page),
  /// ordered by start_datetime then id (stable). Caller stops when fewer than
  /// [limit] rows come back.
  Future<List<Event>> getUpcomingEvents({
    int limit = 20,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = SupabaseConfig.client
          .from('events')
          .select('''
            id, title, description, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''')
          .eq('status', 'active')
          .eq('is_subscriber_only', false)
          .neq('invite_only', true)
          .gte('start_datetime', (startDate ?? DateTime.now()).toIso8601String());

      if (endDate != null) {
        query = query.lte('start_datetime', endDate.toIso8601String());
      }

      final response = await query
          .order('start_datetime', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + limit - 1);

      if (response == null) return [];

      final events = (response as List)
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();

      return events;
    } catch (e) {
      print('❌ Error fetching upcoming events: $e');
      return [];
    }
  }

  /// Get single event by ID
  Future<Event?> getEvent(String eventId) async {
    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select('''
            id, title, description, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''')
          .eq('id', eventId)
          .inFilter('status', ['active', 'hidden'])
          .single();

      return Event.fromJson(response);
    } catch (e) {
      print('❌ Error fetching event: $e');
      return null;
    }
  }

  /// Fetch upcoming events by a specific organizer (for storefront + carousel)
  Future<List<Event>> getEventsByOrganizer(
    String organizerId, {
    String? excludeEventId,
    int limit = 5,
  }) async {
    // Guard against blank organizer ids (legacy/test events) — an empty string
    // is not a valid uuid and would throw a 22P02 Postgrest error.
    if (organizerId.trim().isEmpty) return [];
    try {
      var query = SupabaseConfig.client
          .from('events')
          .select('''
            id, title, description, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''')
          .eq('organizer_id', organizerId)
          .eq('status', 'active')
          .eq('is_subscriber_only', false)
          .neq('invite_only', true)
          .gte('start_datetime', DateTime.now().toIso8601String());

      if (excludeEventId != null) {
        query = query.neq('id', excludeEventId);
      }

      final response = await query
          .order('start_datetime', ascending: true)
          .limit(limit);
      if (response == null) return [];
      return (response as List)
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Error fetching organizer events: $e');
      return [];
    }
  }

  /// Track event view for analytics
  Future<void> trackEventView({
    required String eventId,
    String source = 'map',
  }) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      await SupabaseConfig.client.from('event_views').insert({
        'event_id': eventId,
        'user_id': user?.id,
        'source': source,
      });
    } catch (e) {
      // Silent fail - analytics shouldn't break user experience
      print('⚠️ Failed to track event view: $e');
    }
  }
}
