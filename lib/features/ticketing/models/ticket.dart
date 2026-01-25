import 'package:bitemates/core/config/supabase_config.dart';

class Ticket {
  final String id;
  final String eventId;
  final String eventTitle;
  final String eventVenue;
  final DateTime eventDateTime;
  final String? eventCoverImage;
  final String qrCode;
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
    this.eventCoverImage,
    required this.qrCode,
    required this.pricePaid,
    required this.isUsed,
    this.usedAt,
    required this.createdAt,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      eventTitle: json['event_title'] as String,
      eventVenue: json['event_venue'] as String,
      eventDateTime: DateTime.parse(
        json['event_start'] as String,
      ), // SQL returns 'event_start'
      eventCoverImage: json['event_cover_image'] as String?,
      qrCode: json['qr_code'] as String,
      pricePaid: json['price_paid'] != null
          ? (json['price_paid'] as num).toDouble()
          : 0.0, // Handle missing price
      isUsed: json['status'] == 'used', // SQL returns 'status', check if 'used'
      usedAt:
          json['checked_in_at'] !=
              null // SQL returns 'checked_in_at'
          ? DateTime.parse(json['checked_in_at'] as String)
          : null,
      createdAt: DateTime.parse(
        json['purchase_date'] as String,
      ), // SQL returns 'purchase_date'
    );
  }

  bool get isExpired =>
      DateTime.now().isAfter(eventDateTime.add(Duration(hours: 6)));
  bool get isUpcoming => DateTime.now().isBefore(eventDateTime) && !isUsed;
}

class TicketService {
  /// Fetch all tickets for current user
  Future<List<Ticket>> getUserTickets() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final response = await SupabaseConfig.client.rpc(
        'get_user_tickets',
        params: {'user_id_param': user.id},
      );

      if (response == null) return [];

      final tickets = (response as List)
          .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
          .toList();

      // Sort: upcoming first, then used, then expired
      tickets.sort((a, b) {
        if (a.isUpcoming && !b.isUpcoming) return -1;
        if (!a.isUpcoming && b.isUpcoming) return 1;
        if (a.isUsed && !b.isUsed) return 1;
        if (!a.isUsed && b.isUsed) return -1;
        return b.eventDateTime.compareTo(a.eventDateTime);
      });

      return tickets;
    } catch (e) {
      print('❌ Error fetching tickets: $e');
      rethrow;
    }
  }
}
