import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// A circular liquid-glass button surface carrying an accent [tint].
///
/// Used for the nav FAB and the floating chat bubble so they read as the same
/// material as the nav bar. The tint stays strong on purpose: these are primary
/// actions, so they must keep their accent identity rather than dissolving into
/// whatever is behind them.
///
/// Pass `enabled: false` where the backdrop cannot be sampled — most notably
/// over the Mapbox native platform view, where a lens has nothing to read and
/// collapses to a muddy disc. That path falls back to the original solid accent
/// gradient, which is what shipped before.
class GlassCircle extends StatelessWidget {
  const GlassCircle({
    super.key,
    required this.size,
    required this.tint,
    required this.child,
    this.enabled = true,
  });

  final double size;
  final Color tint;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(tint, Colors.white, 0.30)!, tint],
          ),
        ),
        child: Center(child: child),
      );
    }

    return LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape.roundedRectangle(
          cornerRadius: size / 2,
          borderWidth: 1,
          borderColor: Colors.white.withOpacity(0.5),
        ),
        appearance: LiquidGlassAppearance(
          blur: const LiquidGlassBlur(sigmaX: 2, sigmaY: 2),
          color: tint.withOpacity(0.55),
        ),
        // Tighter and stronger than the nav bar: a small circle needs a visible
        // edge bend to read as glass at all.
        refraction: const LiquidGlassRefraction(
          distortion: 0.18,
          distortionWidth: 16,
        ),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}
