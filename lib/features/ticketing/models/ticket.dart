import 'package:bitemates/core/config/supabase_config.dart';

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
      eventDateTime: DateTime.parse(json['event_start'].toString()),
      eventEndDateTime: json['event_end'] != null
          ? DateTime.parse(json['event_end'].toString())
          : null,
      eventCoverImage: json['event_cover_image']?.toString(),
      ticketNumber: (json['ticket_number'] ?? '').toString(),
      qrCode: (json['qr_code'] ?? '').toString(),
      status: statusString,
      pricePaid: parsedPrice,
      isUsed: statusString == 'used',
      usedAt: json['checked_in_at'] != null
          ? DateTime.parse(json['checked_in_at'].toString())
          : null,
      createdAt: DateTime.parse(json['purchase_date'].toString()),
    );
  }

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
