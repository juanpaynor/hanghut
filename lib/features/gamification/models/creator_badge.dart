/// Partner-authored loyalty badge (team_comms #236–#244).
///
/// Mirrors the live `creator_badges` table:
///   id, organizer_id, name, description, tier, art_url, art_suppressed,
///   criteria jsonb, is_active, holder_count, created_at, updated_at
///
/// Art is partner-uploaded; when [artSuppressed] is true (admin kill-switch) the
/// UI must degrade to a default frame — the earned badge itself never disappears.
class CreatorBadge {
  final String id;
  final String organizerId;
  final String name;
  final String description;
  final String tier;
  final String? artUrl;
  final bool artSuppressed;
  final Map<String, dynamic> criteria;
  final int holderCount;
  final bool isActive;

  const CreatorBadge({
    required this.id,
    required this.organizerId,
    required this.name,
    required this.description,
    required this.tier,
    required this.artUrl,
    required this.artSuppressed,
    required this.criteria,
    required this.holderCount,
    required this.isActive,
  });

  /// Whether real uploaded art is available and allowed to show.
  bool get hasArt => !artSuppressed && artUrl != null && artUrl!.isNotEmpty;

  factory CreatorBadge.fromJson(Map<String, dynamic> json) {
    return CreatorBadge(
      id: json['id'] as String,
      organizerId: (json['organizer_id'] ?? '') as String,
      name: (json['name'] ?? 'Badge') as String,
      description: (json['description'] ?? '') as String,
      tier: (json['tier'] ?? 'bronze') as String,
      artUrl: json['art_url'] as String?,
      artSuppressed: json['art_suppressed'] == true,
      criteria: json['criteria'] is Map
          ? Map<String, dynamic>.from(json['criteria'] as Map)
          : const {},
      holderCount: (json['holder_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] != false,
    );
  }
}

/// A badge a specific user has earned — one row of `user_creator_badges` joined
/// to its `creator_badges` record.
class EarnedCreatorBadge {
  final String id;
  final DateTime earnedAt;
  final String grantType; // e.g. 'manual', 'attendance_count', …
  final CreatorBadge badge;

  const EarnedCreatorBadge({
    required this.id,
    required this.earnedAt,
    required this.grantType,
    required this.badge,
  });

  factory EarnedCreatorBadge.fromJson(Map<String, dynamic> json) {
    // The joined badge arrives under the `badge:creator_badges(*)` alias.
    final badgeJson = json['badge'] ?? json['creator_badges'];
    return EarnedCreatorBadge(
      id: json['id'] as String,
      earnedAt: DateTime.parse(json['earned_at'] as String),
      grantType: (json['grant_type'] ?? 'manual') as String,
      badge: CreatorBadge.fromJson(
        Map<String, dynamic>.from(badgeJson as Map),
      ),
    );
  }
}
