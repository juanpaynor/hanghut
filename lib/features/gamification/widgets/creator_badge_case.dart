import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/services/creator_badge_service.dart';

/// Shared styling for partner badges — tier colours + rarity from holder_count.
class CreatorBadgeStyle {
  static const tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFFFD700),
    'platinum': Color(0xFFE5E4E2),
    'diamond': Color(0xFFB9F2FF),
    'special': Color(0xFF8E88FF),
  };

  static Color tierColor(String tier) =>
      tierColors[tier.toLowerCase()] ?? const Color(0xFF8E88FF);

  /// Steam-style rarity from how many people hold the badge.
  static ({String label, Color color}) rarity(int holderCount) {
    if (holderCount > 0 && holderCount <= 10) {
      return (label: 'Legendary', color: const Color(0xFFFFB020));
    } else if (holderCount <= 50) {
      return (label: 'Rare', color: const Color(0xFF9F7AEA));
    } else if (holderCount <= 250) {
      return (label: 'Uncommon', color: const Color(0xFF4299E1));
    }
    return (label: 'Common', color: const Color(0xFF8A8A99));
  }

  static String holderLabel(int n) {
    if (n <= 0) return 'Be the first to earn this';
    if (n == 1) return 'Held by 1 person';
    return 'Held by ${_compact(n)} people';
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

/// Profile "badge case" — a Steam-style showcase of partner badges a user has
/// earned. Shows up to 6, with "See all" opening the full collection.
///
/// Loads its own data so it can drop into any profile with just a userId.
/// Hidden entirely when the user has earned none.
class CreatorBadgeCase extends StatefulWidget {
  final String userId;
  final bool isOwnProfile;

  const CreatorBadgeCase({
    super.key,
    required this.userId,
    this.isOwnProfile = false,
  });

  @override
  State<CreatorBadgeCase> createState() => _CreatorBadgeCaseState();
}

class _CreatorBadgeCaseState extends State<CreatorBadgeCase> {
  static const int _featuredMax = 6;
  final _service = CreatorBadgeService();

  List<EarnedCreatorBadge> _earned = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CreatorBadgeCase old) {
    super.didUpdateWidget(old);
    // Refetch across a userId change (and, for own profile, after a sign-in the
    // claim step may have just attached email-earned badges — team_comms #243).
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    final earned = await _service.getEarnedBadges(widget.userId);
    if (!mounted) return;
    setState(() {
      _earned = earned;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Stay invisible until we know there's something to show — no empty frame.
    if (_loading || _earned.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final featured = _earned.take(_featuredMax).toList();
    final hasMore = _earned.length > _featuredMax;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.04),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95),
                  Colors.white.withValues(alpha: 0.75),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFA5B0FF), AppTheme.primaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Badge Case',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
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
                  '${_earned.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const Spacer(),
              if (hasMore)
                GestureDetector(
                  onTap: _openFullCase,
                  child: Row(
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final earned = featured[i];
                return CreatorBadgeTile(
                  badge: earned.badge,
                  isDark: isDark,
                  onTap: () => showCreatorBadgeDetail(context, earned),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openFullCase() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorBadgeCaseScreen(
          earned: _earned,
          isOwnProfile: widget.isOwnProfile,
        ),
      ),
    );
  }
}

/// A single framed badge — partner art inside a tier-coloured ring, or a default
/// frame when art is missing/suppressed. Earned badges always render something.
class CreatorBadgeTile extends StatelessWidget {
  final CreatorBadge badge;
  final bool isDark;
  final double size;
  final VoidCallback? onTap;

  const CreatorBadgeTile({
    super.key,
    required this.badge,
    required this.isDark,
    this.size = 60,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tierColor = CreatorBadgeStyle.tierColor(badge.tier);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [tierColor, tierColor.withValues(alpha: 0.55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tierColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(child: _art(tierColor)),
            ),
            const SizedBox(height: 6),
            Text(
              badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _art(Color tierColor) {
    if (badge.hasArt) {
      return CachedNetworkImage(
        imageUrl: badge.artUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _defaultFrame(tierColor),
        // Degrade to the default frame on any load failure — never a broken
        // image; the earned badge must still read as earned.
        errorWidget: (_, __, ___) => _defaultFrame(tierColor),
      );
    }
    return _defaultFrame(tierColor);
  }

  /// Consistent fallback: a tier-tinted disc with a generic emblem, used when
  /// art is absent or suppressed by the admin kill-switch (team_comms #237).
  Widget _defaultFrame(Color tierColor) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [tierColor.withValues(alpha: 0.35), Colors.white],
          radius: 0.95,
        ),
      ),
      child: Icon(
        Icons.workspace_premium_rounded,
        size: size * 0.5,
        color: tierColor,
      ),
    );
  }
}

/// Bottom-sheet detail for a single earned badge — big art, tier, rarity,
/// granting partner, and earned date.
void showCreatorBadgeDetail(BuildContext context, EarnedCreatorBadge earned) {
  final badge = earned.badge;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tierColor = CreatorBadgeStyle.tierColor(badge.tier);
  final rarity = CreatorBadgeStyle.rarity(badge.holderCount);

  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            width: 116,
            height: 116,
            child: CreatorBadgeTile(badge: badge, isDark: isDark, size: 116),
          ),
          const SizedBox(height: 18),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _pill(badge.tier.toUpperCase(), tierColor),
              _pill(rarity.label, rarity.color),
            ],
          ),
          if (badge.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.groups_rounded,
                size: 15,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 6),
              Text(
                CreatorBadgeStyle.holderLabel(badge.holderCount),
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Earned ${_formatDate(earned.earnedAt.toLocal())}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Full-collection grid of every partner badge a user has earned.
class CreatorBadgeCaseScreen extends StatelessWidget {
  final List<EarnedCreatorBadge> earned;
  final bool isOwnProfile;

  const CreatorBadgeCaseScreen({
    super.key,
    required this.earned,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(isOwnProfile ? 'My Badge Case' : 'Badge Case'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 20,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: earned.length,
        itemBuilder: (context, i) {
          final e = earned[i];
          return CreatorBadgeTile(
            badge: e.badge,
            isDark: isDark,
            size: 80,
            onTap: () => showCreatorBadgeDetail(context, e),
          );
        },
      ),
    );
  }
}
