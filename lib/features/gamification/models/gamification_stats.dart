class GamificationStats {
  final String userId;
  final int totalEventsHosted;
  final int totalEventsAttended;
  final int totalConnectionsMade;
  final DateTime updatedAt;

  GamificationStats({
    required this.userId,
    required this.totalEventsHosted,
    required this.totalEventsAttended,
    required this.totalConnectionsMade,
    required this.updatedAt,
  });

  factory GamificationStats.fromJson(Map<String, dynamic> json) {
    return GamificationStats(
      userId: json['user_id'] as String,
      totalEventsHosted: json['total_events_hosted'] as int? ?? 0,
      totalEventsAttended: json['total_events_attended'] as int? ?? 0,
      totalConnectionsMade: json['total_connections_made'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
