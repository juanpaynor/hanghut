import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/utils/date_range.dart';

class Ticket {
  final String id;
  final String eventId;
  final String eventTitle;
  final String eventVenue;
  final DateTime eventDateTime;
  final DateTime? eventEndDateTime;
  final String? eventCoverImage;
  final String ticketNumber;
  final String qrCode;
  final String status; // 'valid', 'used', 'cancelled', 'refunded'
  final double pricePaid;
  final bool isUsed;
  final DateTime? usedAt;
  final DateTime createdAt;
  final String? tier;
  final Map<String, dynamic>? seatInfo; // { section, row, seat, label }

  Ticket({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.eventVenue,
    required this.eventDateTime,
    this.eventEndDateTime,
    this.eventCoverImage,
    required this.ticketNumber,
    required this.qrCode,
    required this.status,
    required this.pricePaid,
    required this.isUsed,
    this.usedAt,
    required this.createdAt,
    this.tier,
    this.seatInfo,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    final String statusString = (json['status'] ?? 'valid').toString();
    // PostgreSQL numeric comes as String from RPC — handle both
    double parsedPrice = 0.0;
    if (json['price_paid'] != null) {
      final raw = json['price_paid'];
      if (raw is num) {
        parsedPrice = raw.toDouble();
      } else {
        parsedPrice = double.tryParse(raw.toString()) ?? 0.0;
      }
    }

    return Ticket(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      eventTitle: (json['event_title'] ?? 'Event').toString(),
      eventVenue: (json['event_venue'] ?? 'Venue').toString(),
      // These are timestamptz from the DB (UTC). Convert to the device's local
      // zone so the ticket shows the real event time — without .toLocal() a
      // 7:00 PM Manila (UTC+8) event renders as its raw 11:00 UTC value.
      eventDateTime: DateTime.parse(json['event_start'].toString()).toLocal(),
      eventEndDateTime: json['event_end'] != null
          ? DateTime.parse(json['event_end'].toString()).toLocal()
          : null,
      eventCoverImage: json['event_cover_image']?.toString(),
      ticketNumber: (json['ticket_number'] ?? '').toString(),
      qrCode: (json['qr_code'] ?? '').toString(),
      status: statusString,
      pricePaid: parsedPrice,
      isUsed: statusString == 'used',
      usedAt: json['checked_in_at'] != null
          ? DateTime.parse(json['checked_in_at'].toString()).toLocal()
          : null,
      createdAt: DateTime.parse(json['purchase_date'].toString()).toLocal(),
      tier: (json['tier'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['tier'] as String?,
      seatInfo: json['seat_info'] is Map
          ? Map<String, dynamic>.from(json['seat_info'] as Map)
          : null,
    );
  }

  /// Human-readable seat label. Web pre-builds `label` (e.g. "AA1"); fall back
  /// to composing section · row · seat if it's ever missing (team_comms #163).
  String? get seatLabel {
    final info = seatInfo;
    if (info == null || info.isEmpty) return null;
    final label = info['label'];
    if (label != null && label.toString().trim().isNotEmpty) {
      return label.toString();
    }
    final parts = [info['section'], info['row'], info['seat']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .map((p) => p.toString())
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Section name when present (shown alongside the seat label on the card).
  String? get seatSection {
    final s = seatInfo?['section'];
    return (s != null && s.toString().trim().isNotEmpty) ? s.toString() : null;
  }

  /// Nicely-cased tier for display (e.g. "general_admission" -> "General Admission").
  String? get tierLabel {
    final t = tier;
    if (t == null || t.trim().isEmpty) return null;
    return t
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// True when the event spans more than one calendar day.
  bool get isMultiDay => isMultiDayRange(eventDateTime, eventEndDateTime);

  /// Compact multi-day span like "Aug 29 – 30". Only call when [isMultiDay].
  String get dateRangeLabel => formatDateRange(eventDateTime, eventEndDateTime!);

  /// Multi-day span plus start time, "Aug 29 – 30 · 7:00 PM". Only when [isMultiDay].
  String get dateRangeWithTimeLabel =>
      formatDateRangeWithTime(eventDateTime, eventEndDateTime!);

  // Status getters
  bool get isCancelled => status == 'cancelled';
  bool get isRefunded => status == 'refunded';
  bool get isValid => status == 'valid';

  // Expiry logic: Use event end if available, otherwise start + 6 hours
  bool get isExpired {
    final now = DateTime.now();
    final expiryTime =
        eventEndDateTime ?? eventDateTime.add(Duration(hours: 6));
    return now.isAfter(expiryTime);
  }

  bool get isUpcoming =>
      DateTime.now().isBefore(eventDateTime) &&
      !isUsed &&
      !isCancelled &&
      !isRefunded;
}

class TicketService {
  // Cache the full ticket list to avoid redundant RPC calls on pagination
  List<Ticket>? _cachedTickets;

  /// Fetch tickets for the current user.
  /// Caches the full list on first call; subsequent requests paginate from cache.
  /// Pass [forceRefresh] = true to invalidate cache (e.g. pull-to-refresh).
  Future<List<Ticket>> getUserTickets({
    int limit = 15,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    // Return from cache if available
    if (_cachedTickets != null && !forceRefresh) {
      return _paginateFromCache(limit, offset);
    }

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final response = await SupabaseConfig.client.rpc(
        'get_user_tickets',
        params: {'user_id_param': user.id},
      );

      if (response == null) {
        _cachedTickets = [];
        return [];
      }

      final List<Ticket> allTickets = [];
      for (final item in (response as List)) {
        try {
          allTickets.add(Ticket.fromJson(item as Map<String, dynamic>));
        } catch (e) {
          print('⚠️ Failed to parse ticket: $e');
        }
      }

      print('🎟️ Fetched ${allTickets.length} tickets from RPC');

      // Sort newest first for consistent pagination
      allTickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _cachedTickets = allTickets;
      return _paginateFromCache(limit, offset);
    } catch (e) {
      print('❌ Error fetching tickets: $e');
      rethrow;
    }
  }

  List<Ticket> _paginateFromCache(int limit, int offset) {
    final cache = _cachedTickets!;
    if (offset >= cache.length) return [];
    final end = (offset + limit).clamp(0, cache.length);
    final page = cache.sublist(offset, end);
    print('🎟️ Page: offset=$offset, limit=$limit, returning ${page.length} tickets');
    return page;
  }

  /// Invalidate cache (call on pull-to-refresh or after a new purchase)
  void clearCache() => _cachedTickets = null;

  /// Total ticket count (for UI display), or null if not yet loaded
  int? get totalCount => _cachedTickets?.length;
}
