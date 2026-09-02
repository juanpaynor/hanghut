import 'package:bitemates/core/utils/date_range.dart';

class Event {
  final String id;
  final String title;
  final String description;

  /// Rich HTML description as authored on the web dashboard (paragraphs, bold,
  /// bullets, hyperlinks). The plain [description] is a tag-stripped fallback.
  /// Null for events created before this field or via paths that don't set it.
  final String? descriptionHtml;

  final String venueName;
  final String venueAddress;
  final double latitude;
  final double longitude;
  final DateTime startDatetime;
  final DateTime? endDatetime;
  final String? coverImageUrl;
  final List<String> imageUrls;
  final double ticketPrice;
  final int capacity;
  final int ticketsSold;
  final int maxSeatsPerOrder;
  final String category;
  final String organizerId;

  /// Whether this event has a real organizer (some legacy/test events have a
  /// blank organizer_id, which must never be used in UUID-typed queries).
  bool get hasOrganizer => organizerId.trim().isNotEmpty;

  final String? organizerName;
  final String? organizerPhotoUrl;
  final bool organizerVerified;
  final String status;
  final DateTime createdAt;

  // External ticketing (PPC)
  final bool isExternal;
  final String? externalTicketUrl;
  final String? externalProviderName;

  // Luma-style features
  final bool requireApproval;
  final bool hideVenueUntilRegistered;

  // Subscriptions
  final int? subscriberEarlyAccessHours;
  final bool isSubscriberOnly;

  // Active-tier price range — the true source of price truth, since
  // events.ticket_price is NOT kept in sync with tier edits on the dashboard.
  // Enriched after fetch via get_events_price_ranges (null/0 when not loaded or
  // the event has no tiers → callers fall back to ticketPrice).
  double? minTierPrice;
  double? maxTierPrice;
  int tierCount = 0;

  bool get hasTierPricing => tierCount > 0 && minTierPrice != null;

  /// Cheapest price to advertise. Prefers the lowest active tier (always
  /// current); falls back to ticketPrice when tiers aren't known.
  double get displayFromPrice =>
      hasTierPricing ? minTierPrice! : ticketPrice;

  /// Formatted price label. With tiers: a single price for one tier,
  /// "From ₱min" ([range] false) or "₱min – ₱max" ([range] true) for several.
  /// Without tier info: the single ticketPrice (external events get "From ₱").
  String priceLabel({bool range = false, String currency = '₱'}) {
    if (hasTierPricing) {
      final min = minTierPrice!;
      final max = maxTierPrice ?? min;
      if (min <= 0 && max <= 0) return 'Free';
      if (max > min) {
        return range
            ? '$currency${min.toStringAsFixed(0)} – $currency${max.toStringAsFixed(0)}'
            : 'From $currency${min.toStringAsFixed(0)}';
      }
      return '$currency${min.toStringAsFixed(0)}';
    }
    if (ticketPrice <= 0) return 'Free';
    return isExternal
        ? 'From $currency${ticketPrice.toStringAsFixed(0)}'
        : '$currency${ticketPrice.toStringAsFixed(0)}';
  }

  /// Populates the tier price range in place (from get_events_price_ranges).
  void applyPriceRange({
    required double min,
    required double max,
    required int count,
  }) {
    minTierPrice = min;
    maxTierPrice = max;
    tierCount = count;
  }

  Event({
    required this.id,
    required this.title,
    required this.description,
    this.descriptionHtml,
    required this.venueName,
    required this.venueAddress,
    required this.latitude,
    required this.longitude,
    required this.startDatetime,
    this.endDatetime,
    this.coverImageUrl,
    this.imageUrls = const [],
    required this.ticketPrice,
    required this.capacity,
    required this.ticketsSold,
    this.maxSeatsPerOrder = 10,
    required this.category,
    required this.organizerId,
    this.organizerName,
    this.organizerPhotoUrl,
    this.organizerVerified = false,
    this.status = 'active',
    required this.createdAt,
    this.passFeesToCustomer,
    this.passFixedToCustomer,
    this.passPercentageToCustomer,
    this.fixedFeePerTicket,
    this.customPercentage,
    this.isExternal = false,
    this.externalTicketUrl,
    this.externalProviderName,
    this.requireApproval = false,
    this.hideVenueUntilRegistered = false,
    this.subscriberEarlyAccessHours,
    this.isSubscriberOnly = false,
  });

  final bool? passFeesToCustomer;
  // Two independent fee pass-through toggles (supersede passFeesToCustomer,
  // team_comms #197): default passFixed=true, passPercentage=false.
  final bool? passFixedToCustomer;
  final bool? passPercentageToCustomer;
  final double? fixedFeePerTicket;
  final double? customPercentage;

  /// Event start/end converted to the DEVICE's local time — use these for
  /// DISPLAY. The stored value is UTC (timestamptz); formatting startDatetime
  /// directly prints UTC (e.g. 11:00 AM instead of 7:00 PM PHT). Keep using
  /// startDatetime/endDatetime for comparisons and serialization (instants).
  DateTime get startLocal => startDatetime.toLocal();
  DateTime? get endLocal => endDatetime?.toLocal();

  /// True when the event spans more than one calendar day.
  bool get isMultiDay => isMultiDayRange(startDatetime, endDatetime);

  /// Compact multi-day span like "Aug 29 – 30". Only call when [isMultiDay].
  String get dateRangeLabel => formatDateRange(startDatetime, endDatetime!);

  /// Multi-day span plus start time, "Aug 29 – 30 · 7:00 PM". Only when [isMultiDay].
  String get dateRangeWithTimeLabel =>
      formatDateRangeWithTime(startDatetime, endDatetime!);

  int get ticketsAvailable => capacity - ticketsSold;
  bool get isSoldOut => ticketsAvailable <= 0;
  bool get isLowAvailability => ticketsAvailable > 0 && ticketsAvailable < 10;
  bool get isHidden => status == 'hidden';

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      descriptionHtml: json['description_html'] as String?,
      venueName: json['venue_name'] as String,
      venueAddress: (json['venue_address'] ?? json['address'] ?? '') as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      startDatetime: DateTime.parse(json['start_datetime'] as String),
      endDatetime: json['end_datetime'] != null
          ? DateTime.parse(json['end_datetime'] as String)
          : null,
      coverImageUrl: json['cover_image_url'] as String?,
      imageUrls:
          (json['images'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      ticketPrice: (json['ticket_price'] as num).toDouble(),
      capacity: json['capacity'] as int,
      ticketsSold: json['tickets_sold'] as int? ?? 0,
      // Floor at 1: callers use this as a clamp() upper bound, which throws
      // if it ever came back 0 from a misconfigured row.
      maxSeatsPerOrder: switch (json['max_seats_per_order'] as int? ?? 10) {
        < 1 => 1,
        final v => v,
      },
      category: (json['category'] ?? json['event_type'] ?? '') as String,
      organizerId: (json['organizer_id'] as String?) ?? '',
      status: json['status'] as String? ?? 'active',
      organizerName: json['organizer_name'] as String?,
      organizerPhotoUrl: json['organizer_photo_url'] as String?,
      organizerVerified: json['organizer_verified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      passFeesToCustomer: json['partners']?['pass_fees_to_customer'] as bool?,
      passFixedToCustomer:
          json['partners']?['pass_fixed_to_customer'] as bool?,
      passPercentageToCustomer:
          json['partners']?['pass_percentage_to_customer'] as bool?,
      fixedFeePerTicket: (json['partners']?['fixed_fee_per_ticket'] as num?)
          ?.toDouble(),
      customPercentage: (json['partners']?['custom_percentage'] as num?)
          ?.toDouble(),
      isExternal: json['is_external'] as bool? ?? false,
      externalTicketUrl: json['external_ticket_url'] as String?,
      externalProviderName: json['external_provider_name'] as String?,
      requireApproval: json['require_approval'] as bool? ?? false,
      hideVenueUntilRegistered: json['hide_venue_until_registered'] as bool? ?? false,
      subscriberEarlyAccessHours: json['subscriber_early_access_hours'] as int?,
      isSubscriberOnly: json['is_subscriber_only'] as bool? ?? false,
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
      'max_seats_per_order': maxSeatsPerOrder,
      'category': category,
      'organizer_id': organizerId,
      'organizer_name': organizerName,
      'organizer_photo_url': organizerPhotoUrl,
      'organizer_verified': organizerVerified,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
