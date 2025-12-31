import 'package:flutter/material.dart';

class LiquidMorphRoute extends PageRouteBuilder {
  final Widget page;
  final Offset center;

  LiquidMorphRoute({required this.page, required this.center})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        opaque: false, // Vital for seeing the map behind!
        barrierColor: Colors.black54, // Dim background
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 500), // Match closing
        reverseTransitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Fluid easing curve
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn, // Match closing curve
            reverseCurve: Curves.fastOutSlowIn,
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;

              // Calculate max radius needed to cover the screen from the center point
              final double maxRadius = _distanceToFurthestCorner(center, size);

              // Start with a small radius (marker size/2 roughly 30)
              final double startRadius = 30.0;

              return AnimatedBuilder(
                animation: curve,
                builder: (context, child) {
                  // 1. Reveal Animation (Clipping)
                  final double radius =
                      startRadius + (maxRadius - startRadius) * curve.value;

                  // 2. Scale Animation (Slight expansion feel)
                  // We start slightly smaller and expand to 1.0
                  final double scale = 0.8 + (0.2 * curve.value);

                  // 3. Fade IN (Opacity)
                  // We maintain opacity 1 mostly, but maybe fade in slightly at start?
                  // Actually, for "Morph", we want it solid.

                  return ClipOval(
                    clipper: _CircleClipper(center, radius),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment
                          .center, // or alignment based on touch point?
                      // Let's settle for simple reveal for stability first.
                      // Ideally, we translate the child to align with the touch point, but that's complex.
                      child: child,
                    ),
                  );
                },
                child: child,
              );
            },
          );
        },
      );

  static double _distanceToFurthestCorner(Offset point, Size size) {
    // Distances to all 4 corners
    final d1 = (point - const Offset(0, 0)).distance;
    final d2 = (point - Offset(size.width, 0)).distance;
    final d3 = (point - Offset(0, size.height)).distance;
    final d4 = (point - Offset(size.width, size.height)).distance;
    return [d1, d2, d3, d4].reduce((a, b) => a > b ? a : b);
  }
}

class _CircleClipper extends CustomClipper<Rect> {
  final Offset center;
  final double radius;

  _CircleClipper(this.center, this.radius);

  @override
  Rect getClip(Size size) {
    return Rect.fromCircle(center: center, radius: radius);
  }

  @override
  bool shouldReclip(_CircleClipper oldClipper) {
    return oldClipper.center != center || oldClipper.radius != radius;
  }
}
