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

  /// Fetch upcoming events for Feed carousel
  Future<List<Event>> getUpcomingEvents({int limit = 10}) async {
    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select('''
            id, title, description, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, organizer_id, status, created_at,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            partners:organizer_id (
              pass_fees_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''')
          .eq('status', 'active')
          .gte('start_datetime', DateTime.now().toIso8601String())
          .order('start_datetime', ascending: true)
          .limit(limit);

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
            capacity, tickets_sold, event_type, organizer_id, status, created_at,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
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
    try {
      var query = SupabaseConfig.client
          .from('events')
          .select('''
            id, title, description, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, organizer_id, status, created_at,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            partners:organizer_id (
              pass_fees_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''')
          .eq('organizer_id', organizerId)
          .eq('status', 'active')
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
