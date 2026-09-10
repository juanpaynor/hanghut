import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/services/creator_badge_service.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_case.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_criteria.dart';
import 'package:bitemates/core/utils/image_url.dart';

/// "Stamps to collect" — a partner's full badge set on their own page, with the
/// ones you hold pressed in colour and the rest still blank.
///
/// This is the piece that gives a viewer a reason to come back: the profile
/// case shows what you already own, which is a record; this shows what is still
/// missing, which is an invitation. The requirement line under a blank stamp
/// comes from the same criteria parser the earned copy uses, so what it asks
/// for is exactly what the Postgres engine will award on.
///
/// Self-loading and self-hiding: an organizer who has authored no badges gets
/// nothing at all, which is currently every organizer but one.
class PartnerCollectionShelf extends StatefulWidget {
  /// `partners.id` — `creator_badges.organizer_id` references it directly.
  final String partnerId;
  final String partnerName;

  const PartnerCollectionShelf({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  @override
  State<PartnerCollectionShelf> createState() => _PartnerCollectionShelfState();
}

class _PartnerCollectionShelfState extends State<PartnerCollectionShelf> {
  List<CreatorBadge> _badges = const [];
  Map<String, EarnedCreatorBadge> _held = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final badges = await CreatorBadgeService().getPartnerBadges(
      widget.partnerId,
    );
    if (!mounted) return;
    if (badges.isEmpty) {
      setState(() => _loaded = true);
      return;
    }

    // Which of these the viewer already holds. One `inFilter` over the badge
    // ids rather than a request per stamp. `earned_at` and `grant_type` come
    // back too, so tapping a collected stamp opens the same sheet it does on
    // the profile — with its date and its share button — instead of a
    // second-class copy.
    var held = <String, EarnedCreatorBadge>{};
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final rows = await SupabaseConfig.client
            .from('user_creator_badges')
            .select('id, badge_id, earned_at, grant_type')
            .eq('user_id', uid)
            .inFilter('badge_id', badges.map((b) => b.id).toList());
        final byId = {for (final b in badges) b.id: b};
        for (final r in (rows as List)) {
          final row = Map<String, dynamic>.from(r as Map);
          final badge = byId[row['badge_id']];
          if (badge == null) continue;
          held[badge.id] = EarnedCreatorBadge(
            id: row['id'] as String? ?? '',
            earnedAt:
                DateTime.tryParse(row['earned_at'] as String? ?? '') ??
                DateTime.now(),
            grantType: row['grant_type'] as String? ?? '',
            badge: badge,
          );
        }
      } catch (_) {
        // Fall through — every stamp simply renders as not-yet-earned.
      }
    }

    if (!mounted) return;
    setState(() {
      _badges = badges;
      _held = held;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _badges.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mine = _held.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      // A Material, not a decorated Container: the rows below are InkWells, and
      // an opaque BoxDecoration above the nearest Material swallows every
      // splash — the taps would work while looking dead.
      child: Material(
        // The same paper ground as the profile case, so a stamp reads as the
        // same object wherever it appears.
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFFBFAF7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFEAE5DA),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Stamps to collect',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$mine of ${_badges.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                mine == _badges.length
                    ? 'You have the full set'
                    : 'Earned by turning up to ${widget.partnerName}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              ..._badges.map(
                (b) => _CollectRow(
                  badge: b,
                  earned: _held[b.id],
                  // The row already shows the requirement, but it truncates at
                  // two lines and says nothing about rarity, the partner's own
                  // description, or how many people hold it. Tapping has to lead
                  // somewhere or the shelf reads as broken.
                  onTap: () =>
                      showCreatorBadgeSheet(context, b, earned: _held[b.id]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One stamp with what it takes to get it.
class _CollectRow extends StatelessWidget {
  final CreatorBadge badge;
  final EarnedCreatorBadge? earned;
  final VoidCallback onTap;

  const _CollectRow({
    required this.badge,
    required this.earned,
    required this.onTap,
  });

  bool get held => earned != null;

  @override
  Widget build(BuildContext context) {
    final tier = CreatorBadgeStyle.tierColor(badge.tier);
    // Past tense once you hold it, imperative while you don't — the same
    // sentence, aimed at where the viewer actually stands.
    final line = held
        ? CreatorBadgeCriteria.earnedSummary(
            badge.criteria,
            grantType: earned!.grantType,
          )
        : CreatorBadgeCriteria.requirementSummary(badge.criteria);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _stamp(tier),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    badge.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: held ? null : Colors.grey[600],
                    ),
                  ),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (held)
              Icon(Icons.check_circle_rounded, size: 20, color: tier)
            else
              Text(
                CreatorBadgeStyle.rarity(badge.holderCount).label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: CreatorBadgeStyle.rarity(badge.holderCount).color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Held stamps are pressed in ink; unheld ones are the same shape left blank,
  /// so the set reads as one sheet with gaps rather than two kinds of thing.
  Widget _stamp(Color tier) {
    const size = 52.0;
    final ring = held
        ? tier.withValues(alpha: 0.85)
        : Colors.grey.withValues(alpha: 0.35);

    return Opacity(
      opacity: held ? 1 : 0.55,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 1.6),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: held
                  ? tier.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.25),
            ),
          ),
          child: ClipOval(
            child: badge.hasArt
                ? CachedNetworkImage(
                    imageUrl: ImageUrl.avatar(badge.artUrl!, size),
                    fit: BoxFit.cover,
                    // A stamp you haven't earned shows its shape, not its
                    // picture — the art is part of the reward.
                    color: held ? null : Colors.grey,
                    colorBlendMode: held ? null : BlendMode.saturation,
                    placeholder: (_, __) => _inked(tier),
                    errorWidget: (_, __, ___) => _inked(tier),
                  )
                : _inked(tier),
          ),
        ),
      ),
    );
  }

  Widget _inked(Color tier) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: (held ? tier : Colors.grey).withValues(alpha: 0.16),
    ),
    child: Icon(
      held ? Icons.local_activity_rounded : Icons.lock_outline_rounded,
      size: 22,
      color: (held ? tier : Colors.grey).withValues(alpha: 0.8),
    ),
  );
}
