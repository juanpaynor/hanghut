/// XP thresholds per level (index = level - 1, max level 10)
const List<int> kLevelThresholds = [
  0,
  100,
  300,
  600,
  1000,
  1500,
  2100,
  2800,
  3600,
  4500,
];

int computeLevel(int xp) {
  for (int i = kLevelThresholds.length - 1; i >= 0; i--) {
    if (xp >= kLevelThresholds[i]) return i + 1;
  }
  return 1;
}

/// Returns progress 0.0–1.0 within current level
double levelProgress(int xp) {
  final level = computeLevel(xp);
  final currentThreshold = kLevelThresholds[level - 1];
  final nextThreshold = level < kLevelThresholds.length
      ? kLevelThresholds[level]
      : kLevelThresholds.last + 1000;
  return (xp - currentThreshold) / (nextThreshold - currentThreshold);
}

class GamificationStats {
  final String userId;
  final int totalEventsHosted;
  final int totalEventsAttended;
  final int totalConnectionsMade;
  final int totalCheckins;
  final int totalQrVerified;
  final int uniquePeopleMet;
  final int uniqueLocations;
  final int totalXp;
  final int level;
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
    this.totalXp = 0,
    this.level = 1,
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
      totalXp: json['total_xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
