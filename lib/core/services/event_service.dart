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

      // Same enrichment as every other fetch path: the map feeds the discover
      // list, which renders availability badges, and an un-enriched Event
      // reports its stock as unknown.
      await _enrichWithPriceRanges(events);

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
  /// Enriches events in place with their active-tier price range (min/max/count)
  /// via get_events_price_ranges, so price displays reflect the tiers rather
  /// than the stale events.ticket_price. Best-effort — failures leave the
  /// ticketPrice fallback intact. Public so surfaces that build Events from
  /// other queries (e.g. the storefront's get_storefront RPC) can enrich too.
  Future<void> enrichPriceRanges(List<Event> events) => _enrichWithPriceRanges(events);

  /// Fills in tier price range AND real availability for a page of events.
  ///
  /// Reads `ticket_tiers` directly rather than calling `get_events_price_ranges`:
  /// the RPC returns only prices, and availability has to come from the same
  /// rows to be consistent with them. `ticket_tiers` carries a public SELECT
  /// policy, so this needs no new endpoint — and it stays one round trip, since
  /// the RPC was one too.
  ///
  /// An event with no tiers is left untouched: `tierAvailable` stays null and
  /// the UI says nothing about stock, which is the honest answer for the 225
  /// externally-ticketed events we don't sell.
  Future<void> _enrichWithPriceRanges(List<Event> events) async {
    if (events.isEmpty) return;
    try {
      final ids = events.map((e) => e.id).toList();
      final rows = await SupabaseConfig.client
          .from('ticket_tiers')
          .select(
            'event_id, price, quantity_total, quantity_sold, '
            'is_active, sales_start, sales_end',
          )
          .inFilter('event_id', ids);

      final byEvent = <String, List<Map<String, dynamic>>>{};
      for (final r in (rows as List)) {
        final row = Map<String, dynamic>.from(r as Map);
        (byEvent[row['event_id'].toString()] ??= []).add(row);
      }

      final now = DateTime.now();
      for (final e in events) {
        final tiers = byEvent[e.id];
        if (tiers == null || tiers.isEmpty) continue;

        // Prices: active tiers only, matching what get_events_price_ranges did.
        final prices = tiers
            .where((t) => t['is_active'] != false)
            .map((t) => (t['price'] as num?)?.toDouble() ?? 0)
            .toList()
          ..sort();

        // Availability: only tiers a buyer could actually complete a purchase
        // on right now — active, and inside their sales window. A tier whose
        // sales have closed still holds stock, but none of it is for sale.
        var available = 0;
        for (final t in tiers) {
          if (t['is_active'] == false) continue;
          final start = DateTime.tryParse(t['sales_start'] as String? ?? '');
          final end = DateTime.tryParse(t['sales_end'] as String? ?? '');
          if (start != null && start.isAfter(now)) continue;
          if (end != null && end.isBefore(now)) continue;
          final total = (t['quantity_total'] as num?)?.toInt() ?? 0;
          final sold = (t['quantity_sold'] as num?)?.toInt() ?? 0;
          final left = total - sold;
          if (left > 0) available += left;
        }

        e.applyPriceRange(
          min: prices.isEmpty ? 0 : prices.first,
          max: prices.isEmpty ? 0 : prices.last,
          count: prices.length,
          available: available,
        );
      }
    } catch (e) {
      print('⚠️ Could not enrich event tiers: $e');
    }
  }

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
            id, title, description, description_html, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              pass_fixed_to_customer,
              pass_percentage_to_customer,
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

      await _enrichWithPriceRanges(events);
      return events;
    } catch (e) {
      print('❌ Error fetching upcoming events: $e');
      return [];
    }
  }

  /// Matches a canonical UUID (8-4-4-4-12 hex). Anything else is treated as a
  /// human-readable slug.
  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Get a single event by its UUID **or** its slug.
  ///
  /// Event URLs are slugs now (web #262), so deep links / admin popups can carry
  /// either form. We detect a UUID and query `id`, otherwise query `slug` —
  /// passing a slug to `.eq('id', …)` would throw a 22P02 (invalid uuid) error.
  Future<Event?> getEvent(String eventIdOrSlug) async {
    try {
      final key = eventIdOrSlug.trim();
      if (key.isEmpty) return null;
      final query = SupabaseConfig.client
          .from('events')
          .select('''
            id, slug, title, description, description_html, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              pass_fixed_to_customer,
              pass_percentage_to_customer,
              fixed_fee_per_ticket,
              custom_percentage
            )
          ''');
      final response = await (_uuidRe.hasMatch(key)
              ? query.eq('id', key)
              : query.eq('slug', key))
          .inFilter('status', ['active', 'hidden'])
          .single();

      final event = Event.fromJson(response);
      await _enrichWithPriceRanges([event]);
      return event;
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
            id, title, description, description_html, venue_name, address, latitude, longitude,
            start_datetime, end_datetime, cover_image_url, ticket_price,
            capacity, tickets_sold, event_type, category, organizer_id, status, created_at,
            max_seats_per_order,
            is_external, external_ticket_url, external_provider_name,
            require_approval, hide_venue_until_registered,
            subscriber_early_access_hours, is_subscriber_only,
            partners:organizer_id (
              pass_fees_to_customer,
              pass_fixed_to_customer,
              pass_percentage_to_customer,
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
      final events = (response as List)
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
      await _enrichWithPriceRanges(events);
      return events;
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
