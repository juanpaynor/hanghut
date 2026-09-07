import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/services/creator_badge_cache.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_case.dart';

/// One pinned stamp, sized to sit beside a name in a feed row, comment, chat
/// line or attendee list.
///
/// Deliberately capped at a single badge. Partner-uploaded art next to every
/// name is how a feed turns into a wall of logos, so the pin is the user's one
/// choice and everything else stays on the profile.
///
/// Renders nothing until the badge resolves, and nothing at all if it never
/// does — an unresolved stamp must not reserve space or flash a placeholder in
/// a scrolling list.
class PinnedStamp extends StatefulWidget {
  /// Badge id, normally from `users.featured_creator_badge_ids[0]` — see
  /// [CreatorBadgeCache.pinnedIdFrom].
  final String? badgeId;
  final double size;

  const PinnedStamp({super.key, required this.badgeId, this.size = 15});

  @override
  State<PinnedStamp> createState() => _PinnedStampState();
}

class _PinnedStampState extends State<PinnedStamp> {
  final _cache = CreatorBadgeCache.instance;

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant PinnedStamp old) {
    super.didUpdateWidget(old);
    if (old.badgeId != widget.badgeId) _ensure();
  }

  Future<void> _ensure() async {
    final id = widget.badgeId;
    if (id == null || _cache.isResolved(id)) return;
    await _cache.resolve(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.badgeId;
    if (id == null) return const SizedBox.shrink();

    final badge = _cache.peek(id);
    if (badge == null) return const SizedBox.shrink();

    return _StampMark(badge: badge, size: widget.size);
  }
}

/// The mark itself: partner art inside the platform's ring.
///
/// The ring is not decoration — it's the guardrail from team_comms #237. Inline,
/// at 15px, unframed partner art would be indistinguishable from a verification
/// tick or any other platform affordance, so the frame is what keeps a badge
/// readable as a badge.
class _StampMark extends StatelessWidget {
  final CreatorBadge badge;
  final double size;

  const _StampMark({required this.badge, required this.size});

  @override
  Widget build(BuildContext context) {
    final tierColor = CreatorBadgeStyle.tierColor(badge.tier);

    return Tooltip(
      message: badge.name,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tierColor.withValues(alpha: 0.9), width: 1),
        ),
        child: ClipOval(
          child: badge.hasArt
              ? CachedNetworkImage(
                  imageUrl: badge.artUrl!,
                  fit: BoxFit.cover,
                  // Suppressed or unloadable art still shows an inked disc —
                  // never a broken image, never an empty gap where a badge was.
                  placeholder: (_, __) => _inked(tierColor),
                  errorWidget: (_, __, ___) => _inked(tierColor),
                )
              : _inked(tierColor),
        ),
      ),
    );
  }

  Widget _inked(Color tierColor) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tierColor.withValues(alpha: 0.55),
        ),
      );
}

/// An avatar wearing its owner's pinned stamp as a rarity ring.
///
/// The ring colour comes from the pinned badge's rarity (holder_count), so the
/// scarce ones read differently at a glance without needing a label. Wrapping
/// rather than replacing the avatar keeps every existing avatar call site valid.
///
/// When there's no pinned badge — or it hasn't resolved — this renders [child]
/// completely untouched, at the same size. No layout shift either way.
class StampedAvatar extends StatefulWidget {
  final String? badgeId;
  final Widget child;

  /// Diameter of the avatar inside the ring. The ring is drawn outside this.
  final double avatarSize;
  final double ringWidth;

  const StampedAvatar({
    super.key,
    required this.badgeId,
    required this.child,
    required this.avatarSize,
    this.ringWidth = 2,
  });

  @override
  State<StampedAvatar> createState() => _StampedAvatarState();
}

class _StampedAvatarState extends State<StampedAvatar> {
  final _cache = CreatorBadgeCache.instance;

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant StampedAvatar old) {
    super.didUpdateWidget(old);
    if (old.badgeId != widget.badgeId) _ensure();
  }

  Future<void> _ensure() async {
    final id = widget.badgeId;
    if (id == null || _cache.isResolved(id)) return;
    await _cache.resolve(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.badgeId;
    final badge = id == null ? null : _cache.peek(id);
    if (badge == null) return widget.child;

    final ringColor = CreatorBadgeStyle.rarity(badge.holderCount).color;
    final gap = widget.ringWidth * 0.9;

    return Container(
      width: widget.avatarSize + (widget.ringWidth + gap) * 2,
      height: widget.avatarSize + (widget.ringWidth + gap) * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: widget.ringWidth),
      ),
      child: Center(
        child: SizedBox(
          width: widget.avatarSize,
          height: widget.avatarSize,
          child: widget.child,
        ),
      ),
    );
  }
}
