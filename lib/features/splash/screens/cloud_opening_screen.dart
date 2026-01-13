import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

class CloudOpeningScreen extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const CloudOpeningScreen({super.key, required this.onAnimationComplete});

  @override
  State<CloudOpeningScreen> createState() => _CloudOpeningScreenState();
}

class _CloudOpeningScreenState extends State<CloudOpeningScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_CloudLayerData> _clouds = [];
  final Random _random = Random();
  Timer? _timeoutTimer;
  bool _animationCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // 3s flight duration
    );

    // Create a dense tunnel of clouds
    // Layer 0: Deep background (small, covering holes)
    // Layer 1: Midground (flying past)
    // Layer 2: Foreground (whoosh)

    // We generate 12 clouds to ensure coverage
    for (int i = 0; i < 12; i++) {
      bool isLeft = _random.nextBool();
      // Distribute loosely around center
      double alignX = (_random.nextDouble() - 0.5) * 0.8;
      double alignY = (_random.nextDouble() - 0.5) * 0.8;

      _clouds.add(
        _CloudLayerData(
          asset: isLeft
              ? 'assets/images/cloud_left.png'
              : 'assets/images/cloud_right.png',
          alignment: Alignment(alignX, alignY),
          // Explode outwards
          targetAlignment: Alignment(alignX * 8, alignY * 8),
          startScale: 0.8 + _random.nextDouble(),
          targetScale: 5.0 + _random.nextDouble() * 5.0, // Massive scale up
        ),
      );
    }

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_animationCompleted) {
        _animationCompleted = true;
        _timeoutTimer?.cancel();
        widget.onAnimationComplete();
      }
    });

    // Safety timeout: Force completion after 5 seconds
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_animationCompleted) {
        _animationCompleted = true;
        widget.onAnimationComplete();
      }
    });

    // Start
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _controller.value > 0.8,
      child: Stack(
        children: [
          // White Fade-out backing to hide map loading artifacts initially
          // This replaces the "Blue Sky" but serves the same purpose of blocking the view
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                // Fade out faster (by 40% of animation) to reveal map through clouds
                opacity: (1.0 - _controller.value * 2.5).clamp(0.0, 1.0),
                child: Container(color: Colors.white),
              );
            },
          ),

          // Cloud Tunnel
          ..._clouds.map((cloud) => _buildCloudLayer(cloud)),

          // Skip button (appears after 2 seconds as safety)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Show skip button after 2 seconds (66% of 3s animation)
              if (_controller.value < 0.66) return const SizedBox.shrink();

              return Positioned(
                bottom: 40,
                right: 20,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (!_animationCompleted) {
                        _animationCompleted = true;
                        _timeoutTimer?.cancel();
                        widget.onAnimationComplete();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLayer(_CloudLayerData data) {
    // Non-linear acceleration for "flight" feel
    final curvedAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInExpo, // Slow start, fast finish
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = curvedAnim.value;

        // Interpolate Alignment (Spread Out)
        final currentAlign = Alignment.lerp(
          data.alignment,
          data.targetAlignment,
          progress,
        )!;

        // Interpolate Scale (Zoom In)
        final currentScale = lerpDouble(
          data.startScale,
          data.targetScale,
          progress,
        )!;

        // Fade out at very end
        final opacity = (1.0 - (progress - 0.7) * 3).clamp(0.0, 1.0);

        return Align(
          alignment: currentAlign,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: currentScale,
              child: Image.asset(
                data.asset,
                width: MediaQuery.of(context).size.width * 0.7,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  double? lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}

class _CloudLayerData {
  final String asset;
  final Alignment alignment;
  final Alignment targetAlignment;
  final double startScale;
  final double targetScale;

  _CloudLayerData({
    required this.asset,
    required this.alignment,
    required this.targetAlignment,
    required this.startScale,
    required this.targetScale,
  });
}
