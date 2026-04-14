import 'dart:math';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/features/gamification/models/badge.dart';

/// Full-screen celebration overlay shown when a user earns a new badge.
/// Features animated glow, confetti particles, and auto-dismiss.
class BadgeEarnedOverlay extends StatefulWidget {
  final Badge badge;
  final VoidCallback? onDismiss;

  const BadgeEarnedOverlay({
    super.key,
    required this.badge,
    this.onDismiss,
  });

  /// Show as a full-screen overlay on top of the current screen
  static Future<void> show(BuildContext context, Badge badge) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Badge Earned',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim, secondaryAnim) {
        return BadgeEarnedOverlay(
          badge: badge,
          onDismiss: () => Navigator.of(ctx).pop(),
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<BadgeEarnedOverlay> createState() => _BadgeEarnedOverlayState();
}

class _BadgeEarnedOverlayState extends State<BadgeEarnedOverlay>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _confettiController;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Confetti rain
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();

    _particles = List.generate(
      40,
      (_) => _ConfettiParticle.random(),
    );

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  IconData _badgeIcon() {
    switch (widget.badge.iconKey) {
      case 'handshake':
        return Icons.handshake;
      case 'fire':
        return Icons.local_fire_department;
      case 'people':
        return Icons.people;
      case 'explore':
        return Icons.explore;
      case 'star':
        return Icons.star;
      default:
        return Icons.emoji_events;
    }
  }

  Color _tierColor() {
    switch (widget.badge.tier) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      case 'diamond':
        return const Color(0xFFB9F2FF);
      default:
        return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor();
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Confetti layer
          AnimatedBuilder(
            animation: _confettiController,
            builder: (context, child) {
              return CustomPaint(
                size: size,
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _confettiController.value,
                  screenSize: size,
                ),
              );
            },
          ),

          // Badge content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tier label
                Text(
                  widget.badge.tier.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tierColor,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),

                // Badge icon with glow
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glowValue =
                        0.3 + (_glowController.value * 0.4);
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            tierColor.withOpacity(glowValue),
                            tierColor.withOpacity(0.05),
                          ],
                          radius: 0.9,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tierColor.withOpacity(glowValue * 0.6),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _badgeIcon(),
                        size: 56,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Badge name
                Text(
                  widget.badge.name,
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Badge description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    widget.badge.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Dismiss button
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
                    'Awesome! 🎉',
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
}

// ──── Confetti System ────

class _ConfettiParticle {
  final double x; // 0..1
  final double speed; // fall speed factor
  final double size;
  final Color color;
  final double rotation;
  final double wobble; // horizontal oscillation

  _ConfettiParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.wobble,
  });

  factory _ConfettiParticle.random() {
    final rng = Random();
    const colors = [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF6B6B), // Red
      Color(0xFF48BB78), // Green
      Color(0xFF4299E1), // Blue
      Color(0xFFED64A6), // Pink
      Color(0xFFF6E05E), // Yellow
      Color(0xFF9F7AEA), // Purple
    ];
    return _ConfettiParticle(
      x: rng.nextDouble(),
      speed: 0.5 + rng.nextDouble() * 1.0,
      size: 4 + rng.nextDouble() * 8,
      color: colors[rng.nextInt(colors.length)],
      rotation: rng.nextDouble() * 2 * pi,
      wobble: rng.nextDouble() * 30,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;
  final Size screenSize;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = -20 + (screenSize.height + 40) * progress * p.speed;
      final x = p.x * screenSize.width +
          sin(progress * pi * 4 + p.rotation) * p.wobble;

      if (y > screenSize.height) continue;

      final paint = Paint()
        ..color = p.color.withOpacity(1.0 - progress * 0.5)
        ..style = PaintingStyle.fill;

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
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
