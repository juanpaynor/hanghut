class GamificationStats {
  final String userId;
  final int totalEventsHosted;
  final int totalEventsAttended;
  final int totalConnectionsMade;
  final int totalCheckins;
  final int totalQrVerified;
  final int uniquePeopleMet;
  final int uniqueLocations;
  final DateTime updatedAt;

  GamificationStats({
    required this.userId,
    required this.totalEventsHosted,
    required this.totalEventsAttended,
    required this.totalConnectionsMade,
    this.totalCheckins = 0,
    this.totalQrVerified = 0,
    this.uniquePeopleMet = 0,
    this.uniqueLocations = 0,
    required this.updatedAt,
  });

  factory GamificationStats.fromJson(Map<String, dynamic> json) {
    return GamificationStats(
      userId: json['user_id'] as String,
      totalEventsHosted: json['total_events_hosted'] as int? ?? 0,
      totalEventsAttended: json['total_events_attended'] as int? ?? 0,
      totalConnectionsMade: json['total_connections_made'] as int? ?? 0,
      totalCheckins: json['total_checkins'] as int? ?? 0,
      totalQrVerified: json['total_qr_verified'] as int? ?? 0,
      uniquePeopleMet: json['unique_people_met'] as int? ?? 0,
      uniqueLocations: json['unique_locations'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
