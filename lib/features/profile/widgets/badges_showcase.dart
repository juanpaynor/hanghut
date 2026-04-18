import 'package:flutter/material.dart' hide Badge;
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/models/user_badge.dart';

/// A horizontal scrollable badge showcase for profile screens.
/// Earned badges are rendered in full color; unearned ones are greyed/locked.
class BadgesShowcase extends StatelessWidget {
  final List<Badge> allBadges;
  final List<UserBadge> earnedBadges;
  final bool isOwnProfile;

  const BadgesShowcase({
    super.key,
    required this.allBadges,
    required this.earnedBadges,
    this.isOwnProfile = false,
  });

  static const _tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFFFD700),
    'platinum': Color(0xFFE5E4E2),
  };

  // Per-badge slug icons — unique & descriptive for each badge
  static const _slugIcons = {
    'host_bronze': Icons.restaurant_rounded, // 🍽️ Rookie Host
    'host_silver': Icons.local_fire_department_rounded, // 🔥 Regular Host
    'host_gold': Icons.star_rounded, // ⭐ Super Host
    'host_platinum': Icons.diamond_rounded, // 💎 Legendary Host
    'meetup_first': Icons.handshake_rounded, // 🤝 First Real Activity
    'meetup_regular': Icons.local_fire_department_rounded, // 🔥 On Fire
    'meetup_connector': Icons.hub_rounded, // 🕸️ Connector
    'meetup_explorer': Icons.explore_rounded, // 🧭 Explorer
    'social_bronze': Icons.emoji_people_rounded, // 🙋 Newcomer
    'social_silver': Icons.flare_rounded, // 🦋 Social Butterfly
    'social_gold': Icons.celebration_rounded, // 🎉 Life of the Party
    'verified_user': Icons.verified_rounded, // ✅ Verified
  };

  // Fallback by category if slug not mapped
  static const _categoryIcons = {
    'hosting': Icons.campaign_rounded,
    'meetup': Icons.groups_rounded,
    'social': Icons.favorite_rounded,
    'verified': Icons.verified_rounded,
  };

  static IconData _iconFor(Badge badge) {
    return _slugIcons[badge.slug] ??
        _categoryIcons[badge.category] ??
        Icons.emoji_events_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (allBadges.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final earnedIds = earnedBadges.map((e) => e.badgeId).toSet();

    // Sort: earned first (by earned date desc), then unearned
    final sorted = List<Badge>.from(allBadges)
      ..sort((a, b) {
        final aEarned = earnedIds.contains(a.id);
        final bEarned = earnedIds.contains(b.id);
        if (aEarned && !bEarned) return -1;
        if (!aEarned && bEarned) return 1;
        if (aEarned && bEarned) {
          final aDate = earnedBadges
              .firstWhere((e) => e.badgeId == a.id)
              .earnedAt;
          final bDate = earnedBadges
              .firstWhere((e) => e.badgeId == b.id)
              .earnedAt;
          return bDate.compareTo(aDate);
        }
        return 0;
      });

    final earnedCount = earnedIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Text('🏅', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Badges',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$earnedCount/${allBadges.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal scroll of badges
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final badge = sorted[index];
              final isEarned = earnedIds.contains(badge.id);
              return _BadgeChip(
                badge: badge,
                isEarned: isEarned,
                earnedAt: isEarned
                    ? earnedBadges
                          .firstWhere((e) => e.badgeId == badge.id)
                          .earnedAt
                    : null,
                isDark: isDark,
                onTap: () => _showBadgeDetail(
                  context,
                  badge,
                  isEarned,
                  isEarned
                      ? earnedBadges
                            .firstWhere((e) => e.badgeId == badge.id)
                            .earnedAt
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showBadgeDetail(
    BuildContext context,
    Badge badge,
    bool isEarned,
    DateTime? earnedAt,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tierColor = _tierColors[badge.tier] ?? Colors.grey;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge icon large
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isEarned
                      ? LinearGradient(
                          colors: [tierColor, tierColor.withValues(alpha: 0.6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isEarned ? null : Colors.grey.withValues(alpha: 0.2),
                  boxShadow: isEarned
                      ? [
                          BoxShadow(
                            color: tierColor.withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _iconFor(badge),
                  color: isEarned ? Colors.white : Colors.grey,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),

              // Name
              Text(
                badge.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),

              // Tier pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge.tier.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tierColor,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                badge.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),

              // XP reward
              if (badge.xpReward > 0)
                Text(
                  '+${badge.xpReward} XP',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentColor,
                  ),
                ),

              // Earned date or lock message
              const SizedBox(height: 12),
              if (isEarned && earnedAt != null)
                Text(
                  'Earned ${_formatDate(earnedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: Colors.grey.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Not yet earned',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _BadgeChip extends StatelessWidget {
  final Badge badge;
  final bool isEarned;
  final DateTime? earnedAt;
  final bool isDark;
  final VoidCallback onTap;

  const _BadgeChip({
    required this.badge,
    required this.isEarned,
    this.earnedAt,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tierColor = BadgesShowcase._tierColors[badge.tier] ?? Colors.grey;
    final icon = BadgesShowcase._iconFor(badge);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circle icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isEarned
                    ? LinearGradient(
                        colors: [tierColor, tierColor.withValues(alpha: 0.6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isEarned
                    ? null
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.12)),
                boxShadow: isEarned
                    ? [
                        BoxShadow(
                          color: tierColor.withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isEarned ? icon : Icons.lock_outline_rounded,
                color: isEarned
                    ? Colors.white
                    : (isDark
                          ? Colors.white24
                          : Colors.grey.withValues(alpha: 0.4)),
                size: isEarned ? 26 : 20,
              ),
            ),
            const SizedBox(height: 6),
            // Label
            Text(
              badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isEarned ? FontWeight.w600 : FontWeight.w400,
                color: isEarned
                    ? (isDark ? Colors.white70 : Colors.black87)
                    : (isDark ? Colors.white24 : Colors.black26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
