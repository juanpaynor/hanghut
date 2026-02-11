class TicketTier {
  final String id;
  final String eventId;
  final String name;
  final String? description;
  final double price;
  final int quantityTotal;
  final int quantitySold;
  final bool isActive;

  TicketTier({
    required this.id,
    required this.eventId,
    required this.name,
    this.description,
    required this.price,
    required this.quantityTotal,
    required this.quantitySold,
    required this.isActive,
  });

  factory TicketTier.fromJson(Map<String, dynamic> json) {
    return TicketTier(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      quantityTotal: json['quantity_total'] as int,
      quantitySold: json['quantity_sold'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  int get quantityAvailable => quantityTotal - quantitySold;
  bool get isSoldOut => quantityAvailable <= 0;
}
