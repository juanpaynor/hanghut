import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

/// What an organizer has actually done — the proof strip on the partner page.
///
/// Deliberately built from tables the client can already read: `events` carries
/// a public SELECT for non-draft rows, so the archive and the hosting history
/// need no new RPC. The two numbers that would land hardest — how many distinct
/// people have come, and lifetime tickets sold — need aggregates behind
/// `tickets`, which RLS scopes to the buyer and the organizer. Those are a
/// server ask; everything here works today without one.
class PartnerTrackRecord {
  /// Events that have already started. The honest "have they done this before".
  final int pastEvents;

  /// When they started — the first event that has actually happened. Null for
  /// an organizer whose only event is still ahead of them, in which case there
  /// is no history to claim and the strip says something else.
  final DateTime? hostingSince;

  /// Most recent past events, newest first, for the archive.
  final List<Event> archive;

  const PartnerTrackRecord({
    required this.pastEvents,
    required this.hostingSince,
    required this.archive,
  });

  static const empty = PartnerTrackRecord(
    pastEvents: 0,
    hostingSince: null,
    archive: [],
  );

  bool get hasHistory => pastEvents > 0;
}

/// Loads the parts of an organizer's page that `get_storefront` doesn't return.
class PartnerProfileService {
  PartnerProfileService._();
  static final PartnerProfileService _instance = PartnerProfileService._();
  factory PartnerProfileService() => _instance;

  final _supabase = SupabaseConfig.client;

  /// Archive size. Enough to prove a habit without paging a 245-event history.
  static const int _archiveLimit = 12;

  /// Past events plus the counts around them.
  ///
  /// [excludeIds] are the ids already shown under "Next up" — an event that
  /// started yesterday and runs through tomorrow is upcoming by the
  /// storefront's rule (`coalesce(end, start) >= now`) and past by ours, so
  /// without this it would appear in both lists.
  Future<PartnerTrackRecord> loadTrackRecord(
    String partnerId, {
    Set<String> excludeIds = const {},
  }) async {
    if (partnerId.trim().isEmpty) return PartnerTrackRecord.empty;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      final results = await Future.wait<dynamic>([
        // Total past events — a head count, so a 245-event organizer costs the
        // same as a 1-event one.
        _supabase
            .from('events')
            .count()
            .eq('organizer_id', partnerId)
            .neq('status', 'draft')
            .lt('start_datetime', nowIso),
        // The archive itself.
        _supabase
            .from('events')
            .select(
              'id, title, description, cover_image_url, start_datetime, '
              'end_datetime, venue_name, city, ticket_price, capacity, '
              'category, event_type, status',
            )
            .eq('organizer_id', partnerId)
            .neq('status', 'draft')
            .lt('start_datetime', nowIso)
            .order('start_datetime', ascending: false)
            .limit(_archiveLimit + excludeIds.length),
        // The very first one that happened, for "hosting since".
        _supabase
            .from('events')
            .select('start_datetime')
            .eq('organizer_id', partnerId)
            .neq('status', 'draft')
            .lt('start_datetime', nowIso)
            .order('start_datetime', ascending: true)
            .limit(1),
      ]);

      final pastCount = results[0] as int;

      final archive = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => !excludeIds.contains(e['id']))
          .take(_archiveLimit)
          .map(_eventFromJson)
          .toList();

      final firstRows = results[2] as List;
      final since = firstRows.isEmpty
          ? null
          : DateTime.tryParse(
              (firstRows.first as Map)['start_datetime'] as String? ?? '',
            )?.toLocal();

      return PartnerTrackRecord(
        pastEvents: pastCount,
        hostingSince: since,
        archive: archive,
      );
    } catch (e) {
      // The page is worth showing without its history; never block on this.
      // ignore: avoid_print
      print('❌ PartnerProfileService.loadTrackRecord failed: $e');
      return PartnerTrackRecord.empty;
    }
  }

  /// The categories an organizer actually programmes, most-used first.
  ///
  /// Derived from their own events rather than a field they'd have to fill in,
  /// so it's true on day one and stays true as they change what they do.
  static List<String> categoriesOf(Iterable<Event> events) {
    final counts = <String, int>{};
    for (final e in events) {
      final key = e.category.trim();
      if (key.isEmpty || key == 'other') continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(3).toList();
  }

  Event _eventFromJson(Map<String, dynamic> e) {
    return Event(
      id: e['id'] as String,
      title: e['title'] as String? ?? 'Event',
      description: e['description'] as String? ?? '',
      venueName: e['venue_name'] as String? ?? '',
      venueAddress: '',
      latitude: 0,
      longitude: 0,
      startDatetime:
          DateTime.tryParse(e['start_datetime'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      endDatetime: e['end_datetime'] != null
          ? DateTime.tryParse(e['end_datetime'] as String)
          : null,
      coverImageUrl: e['cover_image_url'] as String?,
      ticketPrice: (e['ticket_price'] as num?)?.toDouble() ?? 0,
      capacity: (e['capacity'] as num?)?.toInt() ?? 0,
      ticketsSold: 0,
      // Same fallback as the storefront: new taxonomy first, legacy enum after
      // (team_comms #226).
      category: (e['category'] ?? e['event_type']) as String? ?? 'other',
      organizerId: '',
      createdAt: DateTime.now(),
    );
  }
}
