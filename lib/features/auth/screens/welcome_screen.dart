import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:bitemates/features/auth/screens/signup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Front-door welcome screen shown before login/signup.
///
/// Playful "map motif": a stylized abstract map where location pins drop in
/// with a bounce and pulse, and a few avatar bubbles pop up — echoing the
/// app's core map experience. Forces light theme for a bright, on-brand look
/// (matching [LoginScreen]).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  static const Color _indigo = AppTheme.primaryColor;

  // Drives the staggered pin-drop + content entrance (plays once).
  late final AnimationController _entrance;
  // Continuous pulse rings under the pins.
  late final AnimationController _pulse;
  // Slow continuous pan so the map feels alive (streets + pins parallax).
  late final AnimationController _drift;

  // Landmarks scattered across the map area. Alignment is within the motif box
  // (-1..1). Pins get a pulse ring; avatars show an emoji bubble.
  static const List<_Landmark> _landmarks = [
    _Landmark(Alignment(-0.55, -0.55), start: 0.00, isPin: true),
    _Landmark(Alignment(0.45, -0.72), start: 0.12, emoji: '🎉'),
    _Landmark(Alignment(0.62, -0.18), start: 0.24, isPin: true),
    _Landmark(Alignment(-0.72, 0.15), start: 0.36, emoji: '☕'),
    _Landmark(Alignment(0.02, 0.05), start: 0.48, isPin: true, big: true),
    _Landmark(Alignment(-0.15, 0.62), start: 0.60, emoji: '🎟️'),
    _Landmark(Alignment(0.68, 0.55), start: 0.72, isPin: true),
  ];

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _drift.dispose();
    super.dispose();
  }

  void _goSignup() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(_fadeRoute(const SignupScreen()));
  }

  void _goLogin() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(_fadeRoute(const LoginScreen()));
  }

  Future<void> _handleGoogle() async {
    HapticFeedback.mediumImpact();
    final auth = context.read<AuthProvider>();
    try {
      final success = await auth.signInWithGoogle();
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          _fadeRoute(const MainNavigationScreen(), duration: 600),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to sign in with Google. Please try again.',
        );
      }
    }
  }

  Future<void> _handleApple() async {
    HapticFeedback.mediumImpact();
    final auth = context.read<AuthProvider>();
    try {
      final success = await auth.signInWithApple();
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          _fadeRoute(const MainNavigationScreen(), duration: 600),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to sign in with Apple. Please try again.',
        );
      }
    }
  }

  Route _fadeRoute(Widget page, {int duration = 400}) {
    return PageRouteBuilder(
      transitionDuration: Duration(milliseconds: duration),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Bounded height for the map motif so the CTA block is always on screen.
    final motifHeight = (screenH * 0.42).clamp(240.0, 420.0);

    // Force light theme for the bright, playful brand look (like LoginScreen).
    return Theme(
      data: AppTheme.lightTheme,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEEF0FF), Colors.white],
              stops: [0.0, 0.55],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                // Drifting "streets" fill the whole screen so the glass panel
                // always has something live to blur behind it.
                Positioned.fill(child: _buildDriftingStreets()),
                // Playful pins/avatars in the upper area, with parallax drift.
                Positioned(
                  top: 58,
                  left: 8,
                  right: 8,
                  height: motifHeight,
                  child: _buildPins(),
                ),
                // Foreground: wordmark pinned top, glass CTA pinned bottom.
                Column(
                  children: [
                    const SizedBox(height: 10),
                    _wordmark(),
                    const Spacer(),
                    _buildBottomSheet(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordmark() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/logo_4.png',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _indigo,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.location_on, color: Colors.white, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'HangHut',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Full-screen slowly-panning "streets" backdrop. Larger drift amplitude than
  /// the pins so the two layers parallax against each other.
  Widget _buildDriftingStreets() {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, child) {
        final t = _drift.value * 2 * math.pi;
        // Gentle Lissajous pan — never repeats harshly, always in motion.
        final offset = Offset(math.sin(t) * 16, math.cos(t * 0.8) * 12);
        return Transform.translate(offset: offset, child: child);
      },
      // Scaled up ~12% around center so the small pan never reveals an edge.
      child: Transform.scale(
        scale: 1.12,
        child: SizedBox.expand(
          child: CustomPaint(painter: _StreetsPainter(color: _indigo)),
        ),
      ),
    );
  }

  /// Pins + avatar bubbles, drifting with a smaller amplitude (parallax).
  Widget _buildPins() {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, child) {
        final t = _drift.value * 2 * math.pi;
        final offset = Offset(math.sin(t) * 7, math.cos(t * 0.8) * 5);
        return Transform.translate(offset: offset, child: child);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final lm in _landmarks) _buildLandmark(lm, size),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLandmark(_Landmark lm, Size size) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _pulse]),
      builder: (context, _) {
        // Local drop progress for this landmark (staggered window of the run).
        final raw = ((_entrance.value - lm.start) / 0.4).clamp(0.0, 1.0);
        if (raw <= 0) return const SizedBox.shrink();
        final drop = Curves.elasticOut.transform(raw);
        final fade = Curves.easeOut.transform(raw.clamp(0.0, 1.0));
        // Fall from slightly above and settle with the elastic bounce.
        final dy = (1 - drop) * -34.0;

        final child = lm.isPin
            ? _pin(big: lm.big, phase: lm.start)
            : _avatar(lm.emoji!);

        return Align(
          alignment: lm.align,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: 0.6 + 0.4 * drop.clamp(0.0, 1.2),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pin({bool big = false, double phase = 0}) {
    final double dotSize = big ? 22 : 16;
    // Pulse ring: expands + fades continuously, offset per-pin by its phase.
    final t = (_pulse.value + phase) % 1.0;
    final ringScale = 1.0 + t * 2.4;
    final ringOpacity = (1.0 - t) * 0.35;

    return SizedBox(
      width: big ? 84 : 64,
      height: big ? 84 : 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring
          Transform.scale(
            scale: ringScale,
            child: Container(
              width: dotSize + 8,
              height: dotSize + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _indigo.withValues(alpha: ringOpacity),
              ),
            ),
          ),
          // Pin head
          Container(
            width: dotSize + 14,
            height: dotSize + 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: _indigo.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _indigo,
                ),
                child: Icon(
                  Icons.location_on,
                  size: dotSize * 0.7,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String emoji) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
    );
  }

  Widget _buildBottomSheet() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        // Slide + fade the whole CTA block up as the last part of the entrance.
        // NOTE: computed inside the builder so it updates every tick — computing
        // it outside would capture the first-frame value (0) and stay invisible.
        final slide = Curves.easeOutCubic.transform(
          ((_entrance.value - 0.35) / 0.65).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: slide,
          child: Transform.translate(
            offset: Offset(0, (1 - slide) * 24),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.60),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.75),
                  width: 1.5,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(24, 26, 24, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Find your people.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
                height: 1.05,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "See who's out and what's happening around you.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),

            // Primary CTA → Sign up
            ElevatedButton(
              onPressed: _goSignup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Get started',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Continue with Google
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return OutlinedButton.icon(
                  onPressed: auth.isLoading ? null : _handleGoogle,
                  icon: Image.asset(
                    'assets/images/google_logo.png',
                    height: 20,
                    width: 20,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.g_mobiledata, color: Colors.black87),
                  ),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.grey[200]!, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    foregroundColor: Colors.black87,
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Continue with Apple
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return OutlinedButton.icon(
                  onPressed: auth.isLoading ? null : _handleApple,
                  icon: const Icon(
                    Icons.apple,
                    size: 22,
                    color: Colors.black87,
                  ),
                  label: const Text('Continue with Apple'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.grey[200]!, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    foregroundColor: Colors.black87,
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // Log in
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                GestureDetector(
                  onTap: _goLogin,
                  child: Text(
                    'Log in',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _indigo,
                    ),
                  ),
                ),
              ],
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A landmark on the map motif — either a location pin or an emoji avatar.
class _Landmark {
  final Alignment align;
  final double start; // stagger start (0..1 of the entrance run)
  final bool isPin;
  final bool big;
  final String? emoji;

  const _Landmark(
    this.align, {
    required this.start,
    this.isPin = false,
    this.big = false,
    this.emoji,
  });
}

/// Paints a soft, abstract "street map" backdrop behind the pins.
class _StreetsPainter extends CustomPainter {
  final Color color;

  _StreetsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    final w = size.width;
    final h = size.height;

    // A loose set of intersecting avenues + diagonals — reads as a map without
    // being literal.
    final paths = <Path>[
      Path()
        ..moveTo(w * -0.05, h * 0.28)
        ..quadraticBezierTo(w * 0.4, h * 0.18, w * 1.05, h * 0.42),
      Path()
        ..moveTo(w * 0.15, h * -0.05)
        ..quadraticBezierTo(w * 0.35, h * 0.5, w * 0.2, h * 1.05),
      Path()
        ..moveTo(w * 1.05, h * -0.02)
        ..quadraticBezierTo(w * 0.6, h * 0.45, w * 0.75, h * 1.05),
      Path()
        ..moveTo(w * -0.05, h * 0.8)
        ..quadraticBezierTo(w * 0.5, h * 0.72, w * 1.05, h * 0.86),
    ];
    for (final p in paths) {
      canvas.drawPath(p, road);
    }

    // A couple of faint "blocks" for texture.
    final block = Paint()..color = color.withValues(alpha: 0.04);
    void drawBlock(double cx, double cy, double s) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * cx, h * cy), width: s, height: s),
        const Radius.circular(14),
      );
      canvas.drawRRect(rect, block);
    }

    drawBlock(0.22, 0.42, math.min(w, h) * 0.22);
    drawBlock(0.78, 0.3, math.min(w, h) * 0.18);
    drawBlock(0.6, 0.75, math.min(w, h) * 0.2);
  }

  @override
  bool shouldRepaint(covariant _StreetsPainter oldDelegate) => false;
}
