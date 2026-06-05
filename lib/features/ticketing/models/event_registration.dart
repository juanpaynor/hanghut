import 'package:bitemates/core/config/supabase_config.dart';

class EventRegistration {
  final String id;
  final String eventId;
  final String status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? tierId;

  // Embedded event fields
  final String eventTitle;
  final String? eventVenue;
  final DateTime? eventStartDatetime;
  final String? eventCoverImage;
  final double eventTicketPrice;

  EventRegistration({
    required this.id,
    required this.eventId,
    required this.status,
    required this.createdAt,
    required this.eventTitle,
    required this.eventTicketPrice,
    this.rejectionReason,
    this.reviewedAt,
    this.tierId,
    this.eventVenue,
    this.eventStartDatetime,
    this.eventCoverImage,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isFree => eventTicketPrice <= 0;
  bool get awaitingPayment => isApproved && !isFree;

  factory EventRegistration.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>?;
    return EventRegistration(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      status: json['status'] as String,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      tierId: json['tier_id'] as String?,
      eventTitle: event?['title'] as String? ?? 'Event',
      eventVenue: event?['venue_name'] as String?,
      eventStartDatetime: event?['start_datetime'] != null
          ? DateTime.parse(event!['start_datetime'] as String)
          : null,
      eventCoverImage: event?['cover_image_url'] as String?,
      eventTicketPrice: (event?['ticket_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class EventRegistrationService {
  static Future<List<EventRegistration>> getUserRegistrations() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await SupabaseConfig.client
        .from('event_registrations')
        .select(
          'id, event_id, status, rejection_reason, created_at, reviewed_at, tier_id, '
          'event:events(id, title, venue_name, start_datetime, cover_image_url, ticket_price)',
        )
        .eq('user_id', userId)
        .inFilter('status', ['pending', 'approved', 'rejected'])
        .order('created_at', ascending: false);

    return (response as List)
        .map((r) => EventRegistration.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
