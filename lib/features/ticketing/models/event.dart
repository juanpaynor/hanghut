class Event {
  final String id;
  final String title;
  final String description;
  final String venueName;
  final String venueAddress;
  final double latitude;
  final double longitude;
  final DateTime startDatetime;
  final DateTime? endDatetime;
  final String? coverImageUrl;
  final double ticketPrice;
  final int capacity;
  final int ticketsSold;
  final String category;
  final String organizerId;
  final String? organizerName;
  final String? organizerPhotoUrl;
  final bool organizerVerified;
  final DateTime createdAt;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.venueName,
    required this.venueAddress,
    required this.latitude,
    required this.longitude,
    required this.startDatetime,
    this.endDatetime,
    this.coverImageUrl,
    required this.ticketPrice,
    required this.capacity,
    required this.ticketsSold,
    required this.category,
    required this.organizerId,
    this.organizerName,
    this.organizerPhotoUrl,
    this.organizerVerified = false,
    required this.createdAt,
    this.passFeesToCustomer,
    this.fixedFeePerTicket,
    this.customPercentage,
  });

  final bool? passFeesToCustomer;
  final double? fixedFeePerTicket;
  final double? customPercentage;

  int get ticketsAvailable => capacity - ticketsSold;
  bool get isSoldOut => ticketsAvailable <= 0;
  bool get isLowAvailability => ticketsAvailable > 0 && ticketsAvailable < 10;

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      venueName: json['venue_name'] as String,
      venueAddress: json['venue_address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      startDatetime: DateTime.parse(json['start_datetime'] as String),
      endDatetime: json['end_datetime'] != null
          ? DateTime.parse(json['end_datetime'] as String)
          : null,
      coverImageUrl: json['cover_image_url'] as String?,
      ticketPrice: (json['ticket_price'] as num).toDouble(),
      capacity: json['capacity'] as int,
      ticketsSold: json['tickets_sold'] as int? ?? 0,
      category: json['category'] as String,
      organizerId: json['organizer_id'] as String,
      organizerName: json['organizer_name'] as String?,
      organizerPhotoUrl: json['organizer_photo_url'] as String?,
      organizerVerified: json['organizer_verified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      passFeesToCustomer: json['partners']?['pass_fees_to_customer'] as bool?,
      fixedFeePerTicket: (json['partners']?['fixed_fee_per_ticket'] as num?)
          ?.toDouble(),
      customPercentage: (json['partners']?['custom_percentage'] as num?)
          ?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'venue_name': venueName,
      'venue_address': venueAddress,
      'latitude': latitude,
      'longitude': longitude,
      'start_datetime': startDatetime.toIso8601String(),
      'end_datetime': endDatetime?.toIso8601String(),
      'cover_image_url': coverImageUrl,
      'ticket_price': ticketPrice,
      'capacity': capacity,
      'tickets_sold': ticketsSold,
      'category': category,
      'organizer_id': organizerId,
      'organizer_name': organizerName,
      'organizer_photo_url': organizerPhotoUrl,
      'organizer_verified': organizerVerified,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
