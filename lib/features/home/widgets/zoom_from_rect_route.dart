import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// A container-transform style route: [page] appears to grow out of
/// [originRect] — the tapped card's rect in global (screen) coordinates —
/// and collapses back into it on pop. Feels like the story card "opens".
///
/// If [originRect] is null it degrades gracefully to a plain fade, so callers
/// that can't measure an origin (e.g. deep links) still work.
class ZoomFromRectRoute<T> extends PageRouteBuilder<T> {
  final Rect? originRect;
  final Widget page;
  final double originRadius;

  ZoomFromRectRoute({
    required this.page,
    this.originRect,
    this.originRadius = 20,
  }) : super(
          // Transparent + non-opaque so the feed shows behind the growing card.
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            final rect = originRect;
            if (rect == null) {
              return FadeTransition(opacity: curved, child: child);
            }

            final size = MediaQuery.of(context).size;

            return AnimatedBuilder(
              animation: curved,
              builder: (context, _) {
                final t = curved.value;

                // Non-uniform scale so the collapsed frame matches the card
                // footprint exactly, then eases to full-screen.
                final sx = lerpDouble(rect.width / size.width, 1.0, t)!;
                final sy = lerpDouble(rect.height / size.height, 1.0, t)!;
                final dx = lerpDouble(rect.center.dx - size.width / 2, 0, t)!;
                final dy = lerpDouble(rect.center.dy - size.height / 2, 0, t)!;
                final radius = lerpDouble(originRadius, 0, t)!;

                return Stack(
                  children: [
                    // Backdrop fades in as the card grows.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withOpacity(t.clamp(0.0, 1.0) * 0.7),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(dx, dy),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(sx, sy, 1.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
}
