import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/services/creator_badge_service.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_criteria.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_style.dart';
import 'package:bitemates/features/gamification/widgets/stamp_share_card.dart';

// Re-exported so the existing surfaces that reach CreatorBadgeStyle through this
// file keep working after the extraction.
export 'package:bitemates/features/gamification/widgets/creator_badge_style.dart';

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
        // Paper, not a glass trophy case. A stamp page should sit quiet so the
        // partner art is the loudest thing in the section — and a flat ground
        // is what makes ink-on-paper read as ink rather than as a gem.
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFFBFAF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFEAE5DA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Stamps',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${_earned.length}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    // Says the mechanic out loud. A stamp means you were there,
                    // which is what separates these from anything you can buy.
                    Text(
                      widget.isOwnProfile
                          ? 'Collected when you turn up'
                          : 'Collected by turning up',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMore)
                GestureDetector(
                  onTap: _openFullCase,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final earned = featured[i];
                return CreatorBadgeTile(
                  badge: earned.badge,
                  isDark: isDark,
                  earnedAt: earned.earnedAt,
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
  final DateTime? earnedAt;
  final VoidCallback? onTap;

  /// Draw the name (and date) beneath the stamp.
  ///
  /// Off where the surrounding surface already names the badge — the detail
  /// sheet does, and drawing it twice both duplicated the title and pushed the
  /// Column past a caller that had sized its box for the stamp alone.
  final bool showLabel;

  const CreatorBadgeTile({
    super.key,
    required this.badge,
    required this.isDark,
    this.size = 64,
    this.earnedAt,
    this.onTap,
    this.showLabel = true,
  });

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  /// A small per-badge tilt so a row reads as pressed by hand rather than laid
  /// out on a grid. Derived from the id, so a given stamp always leans the same
  /// way — it must not reshuffle on every rebuild. Kept under 3°: enough to feel
  /// stamped, not so much that the art looks crooked.
  double get _tilt => ((badge.id.hashCode.abs() % 9) - 4) * 0.012;

  @override
  Widget build(BuildContext context) {
    final tierColor = CreatorBadgeStyle.tierColor(badge.tier);
    final ink = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        // Extra width is room for the label to wrap into; without one the tile
        // is exactly the stamp, so a caller can size a box to `size` and have it
        // fit precisely.
        width: showLabel ? size + 14 : size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: _tilt,
              child: Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(3),
                // Double ring — the giveaway of a rubber stamp, and the piece
                // web asked for in #237: a consistent platform frame that
                // partner art cannot impersonate. No glow, no gradient; ink on
                // paper doesn't luminesce.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tierColor.withValues(alpha: 0.85),
                    width: 1.6,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tierColor.withValues(alpha: 0.40),
                      width: 1,
                    ),
                  ),
                  // Art renders faithfully inside the frame — partners paid for
                  // that design, so the stamp treatment lives in the rings, not
                  // in a filter over their work.
                  child: ClipOval(child: _art(tierColor)),
                ),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 7),
              Text(
                badge.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: ink.withValues(alpha: isDark ? 0.82 : 0.80),
                ),
              ),
              if (earnedAt != null)
                Text(
                  "${_months[earnedAt!.month - 1]} '${earnedAt!.year % 100}",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: ink.withValues(alpha: isDark ? 0.35 : 0.32),
                  ),
                ),
            ],
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

  /// Consistent fallback used when art is absent or suppressed by the admin
  /// kill-switch (team_comms #237). An earned stamp must still read as earned,
  /// so this is a blank inked disc rather than an error state — it looks like a
  /// stamp whose design simply isn't showing, which is exactly what it is.
  Widget _defaultFrame(Color tierColor) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tierColor.withValues(alpha: isDark ? 0.20 : 0.13),
      ),
      child: Icon(
        Icons.local_activity_outlined,
        size: size * 0.42,
        color: tierColor.withValues(alpha: 0.85),
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
  final earnedReason = CreatorBadgeCriteria.earnedSummary(
    badge.criteria,
    grantType: earned.grantType,
  );

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
          CreatorBadgeTile(
            badge: badge,
            isDark: isDark,
            size: 116,
            // The sheet titles the badge in 22pt directly below; the tile's own
            // label would repeat it and overflow the box.
            showLabel: false,
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
          // How it was earned — the point of a stamp is what you did to get it,
          // and without this the sheet only ever says what you have.
          if (earnedReason.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HOW YOU EARNED IT',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    earnedReason,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
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
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // Close the detail first: the share card is itself a sheet, and
                // stacking two leaves the user two Backs from where they were.
                Navigator.of(context).pop();
                showStampShareCard(
                  context,
                  badge,
                  earnedAt: earned.earnedAt.toLocal(),
                  grantType: earned.grantType,
                );
              },
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: const Text('Share this stamp'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                foregroundColor: isDark ? Colors.white : Colors.black87,
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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
        title: Text(isOwnProfile ? 'My Stamps' : 'Stamps'),
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
            earnedAt: e.earnedAt.toLocal(),
            onTap: () => showCreatorBadgeDetail(context, e),
          );
        },
      ),
    );
  }
}
