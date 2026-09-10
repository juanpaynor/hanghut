import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_criteria.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_style.dart';
import 'package:bitemates/core/utils/image_url.dart';

/// Logical size of the share image. 9:16 so it drops straight into an Instagram
/// or Facebook story without letterboxing; captured at 3x for a 1080x1920 PNG.
const Size _kCardSize = Size(360, 640);
const double _kCapturePixelRatio = 3;

const _months = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// Show the shareable card for an earned stamp, with a Share button.
///
/// The preview isn't only courtesy — capturing a `RepaintBoundary` that holds an
/// unloaded network image yields a blank frame, so putting the card on screen
/// first is what guarantees the partner art is actually painted before we
/// rasterise it.
Future<void> showStampShareCard(
  BuildContext context,
  CreatorBadge badge, {
  DateTime? earnedAt,
  String? grantType,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StampShareSheet(
      badge: badge,
      earnedAt: earnedAt,
      grantType: grantType,
    ),
  );
}

class _StampShareSheet extends StatefulWidget {
  final CreatorBadge badge;
  final DateTime? earnedAt;
  final String? grantType;

  const _StampShareSheet({
    required this.badge,
    this.earnedAt,
    this.grantType,
  });

  @override
  State<_StampShareSheet> createState() => _StampShareSheetState();
}

class _StampShareSheetState extends State<_StampShareSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: _kCapturePixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      // Temp dir, not documents: this is a throwaway artefact of one share and
      // should not accumulate in the user's storage.
      final dir = await getTemporaryDirectory();
      final safeName =
          widget.badge.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final file = File(
        '${dir.path}/hanghut_stamp_$safeName.png',
      );
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Earned "${widget.badge.name}" on HangHut',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't create the image — try again")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Scaled to fit the sheet; the boundary inside still lays out at the
            // full 360x640, so the capture is full resolution regardless.
            Flexible(
              child: FittedBox(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: StampShareCard(
                    badge: widget.badge,
                    earnedAt: widget.earnedAt,
                    grantType: widget.grantType,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(_sharing ? 'Preparing…' : 'Share stamp'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
}

/// The shareable image itself.
///
/// A paper card pressed with the stamp, floating on ink — the same
/// proof-of-presence language as the profile stamps, scaled up to carry on its
/// own outside the app. Committed to one look rather than following the
/// viewer's theme: this becomes a PNG, and a story has no dark mode.
class StampShareCard extends StatelessWidget {
  final CreatorBadge badge;
  final DateTime? earnedAt;
  final String? grantType;

  const StampShareCard({
    super.key,
    required this.badge,
    this.earnedAt,
    this.grantType,
  });

  /// Past-tense description of what earned this, e.g. "One of their first 50
  /// buyers ever". Empty when the criterion type is one this build predates.
  String get earnedReason => CreatorBadgeCriteria.earnedSummary(
        badge.criteria,
        grantType: grantType,
      );

  static const _ink = Color(0xFF16131F);
  static const _inkSoft = Color(0xFF241F33);
  static const _paper = Color(0xFFF4F1E9);
  static const _paperEdge = Color(0xFFDDD6C6);

  @override
  Widget build(BuildContext context) {
    final tierColor = CreatorBadgeStyle.tierColor(badge.tier);
    final rarity = CreatorBadgeStyle.rarity(badge.holderCount);

    return SizedBox(
      width: _kCardSize.width,
      height: _kCardSize.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_inkSoft, _ink],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 34, 28, 26),
          child: Column(
            children: [
              Text(
                'PROOF OF PRESENCE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
              const Spacer(),
              _paperCard(tierColor, rarity),
              const Spacer(),
              Text(
                'HANGHUT',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4.5,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'hanghut.com',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paperCard(Color tierColor, ({String label, Color color}) rarity) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _paperEdge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Same hand-pressed tilt as the profile stamps, so the two surfaces
          // read as the same object rather than two treatments of one idea.
          Transform.rotate(
            angle: ((badge.id.hashCode.abs() % 9) - 4) * 0.014,
            child: _stamp(tierColor),
          ),
          const SizedBox(height: 22),
          Text(
            badge.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 23,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Color(0xFF1A1622),
            ),
          ),
          // What they actually did. Without this the card says only that a
          // stamp exists; with it, the image tells a story a stranger can read
          // and want — which is the whole reason to share it.
          if (earnedReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              earnedReason,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5C5468),
              ),
            ),
          ],
          if (earnedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              "COLLECTED ${_months[earnedAt!.month - 1]} ${earnedAt!.year}",
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: Color(0xFF8A8194),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: rarity.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: rarity.color.withValues(alpha: 0.42)),
            ),
            child: Text(
              badge.holderCount > 0
                  ? '${rarity.label.toUpperCase()} · ${badge.holderCount} HOLD THIS'
                  : rarity.label.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: HSLColor.fromColor(rarity.color)
                    .withLightness(0.34)
                    .toColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stamp(Color tierColor) {
    const size = 150.0;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tierColor.withValues(alpha: 0.9), width: 3),
      ),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tierColor.withValues(alpha: 0.45), width: 1.6),
        ),
        child: ClipOval(
          child: badge.hasArt
              ? CachedNetworkImage(
                  imageUrl: ImageUrl.avatar(badge.artUrl!, size),
                  fit: BoxFit.cover,
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
          color: tierColor.withValues(alpha: 0.18),
        ),
        child: Icon(
          Icons.local_activity_outlined,
          size: 56,
          color: tierColor.withValues(alpha: 0.85),
        ),
      );
}
