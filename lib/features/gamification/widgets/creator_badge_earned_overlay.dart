import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_case.dart';

/// Full-screen celebration when a user earns a partner badge — pulsing tier
/// glow around the partner's art (default frame if none), plus confetti.
class CreatorBadgeEarnedOverlay extends StatefulWidget {
  final CreatorBadge badge;
  final VoidCallback? onDismiss;

  const CreatorBadgeEarnedOverlay({
    super.key,
    required this.badge,
    this.onDismiss,
  });

  static Future<void> show(BuildContext context, CreatorBadge badge) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Badge Earned',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim, __) => CreatorBadgeEarnedOverlay(
        badge: badge,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
      transitionBuilder: (ctx, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<CreatorBadgeEarnedOverlay> createState() =>
      _CreatorBadgeEarnedOverlayState();
}

class _CreatorBadgeEarnedOverlayState extends State<CreatorBadgeEarnedOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _confetti;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _particles = List.generate(40, (_) => _Particle.random());
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  void dispose() {
    _glow.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    final tierColor = CreatorBadgeStyle.tierColor(badge.tier);
    final rarity = CreatorBadgeStyle.rarity(badge.holderCount);
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _confetti,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _ConfettiPainter(_particles, _confetti.value, size),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BADGE EARNED',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: tierColor,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _glow,
                  builder: (_, __) {
                    final g = 0.35 + _glow.value * 0.4;
                    return Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [tierColor, tierColor.withValues(alpha: 0.55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tierColor.withValues(alpha: g * 0.7),
                            blurRadius: 34,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 128,
                        height: 128,
                        child: ClipOval(child: _art(tierColor)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  badge.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: rarity.color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    rarity.label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: rarity.color,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (badge.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      badge.description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: widget.onDismiss,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tierColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Add to my case 🎉',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _art(Color tierColor) {
    if (widget.badge.hasArt) {
      return CachedNetworkImage(
        imageUrl: widget.badge.artUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _fallback(tierColor),
        errorWidget: (_, __, ___) => _fallback(tierColor),
      );
    }
    return _fallback(tierColor);
  }

  Widget _fallback(Color tierColor) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [tierColor.withValues(alpha: 0.4), Colors.white],
            radius: 0.95,
          ),
        ),
        child: Icon(
          Icons.workspace_premium_rounded,
          size: 60,
          color: tierColor,
        ),
      );
}

// ── Confetti ──
class _Particle {
  final double x, speed, size, rotation, wobble;
  final Color color;
  _Particle(this.x, this.speed, this.size, this.color, this.rotation,
      this.wobble);

  factory _Particle.random() {
    final r = Random();
    const colors = [
      Color(0xFFFFD700),
      Color(0xFFFF6B6B),
      Color(0xFF48BB78),
      Color(0xFF4299E1),
      Color(0xFFED64A6),
      Color(0xFF9F7AEA),
    ];
    return _Particle(
      r.nextDouble(),
      0.5 + r.nextDouble(),
      4 + r.nextDouble() * 8,
      colors[r.nextInt(colors.length)],
      r.nextDouble() * 2 * pi,
      r.nextDouble() * 30,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Size screen;
  _ConfettiPainter(this.particles, this.progress, this.screen);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = -20 + (screen.height + 40) * progress * p.speed;
      if (y > screen.height) continue;
      final x =
          p.x * screen.width + sin(progress * pi * 4 + p.rotation) * p.wobble;
      final paint = Paint()..color = p.color.withValues(alpha: 1 - progress * 0.5);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * pi * 2 * p.speed + p.rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      progress != old.progress;
}
