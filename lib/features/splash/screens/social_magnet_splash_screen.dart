import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/main.dart'; // Import for AuthGate
import 'package:bitemates/core/config/supabase_config.dart';

class SocialMagnetSplashScreen extends StatefulWidget {
  const SocialMagnetSplashScreen({super.key});

  @override
  State<SocialMagnetSplashScreen> createState() =>
      _SocialMagnetSplashScreenState();
}

class _SocialMagnetSplashScreenState extends State<SocialMagnetSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _magnetController;

  // List of items (icons) with their random starting positions
  final List<FloatingItem> _items = [];
  final Random _random = Random();

  bool _magnetActive = false;
  bool _impactHappened = false;

  @override
  void initState() {
    super.initState();

    // Setup animation controllers
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _magnetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Generate random items
    _generateItems();

    // Start the sequence
    _startAnimationSequence();
  }

  void _generateItems() {
    // Activity Icons
    final icons = [
      Icons.sports_tennis,
      Icons.sports_basketball,
      Icons.mic,
      Icons.videogame_asset,
      Icons.restaurant,
      Icons.local_cafe,
      Icons.directions_run,
      Icons.music_note,
      Icons.brush,
      Icons.camera_alt,
      Icons.flight,
      Icons.laptop_mac,
    ];

    // Create 20 items with random positions
    for (int i = 0; i < 20; i++) {
      _items.add(
        FloatingItem(
          icon: icons[i % icons.length],
          startPos: Offset(
            (_random.nextDouble() * 2 - 1), // -1 to 1 (screen width rel)
            (_random.nextDouble() * 2 - 1), // -1 to 1 (screen height rel)
          ),
          driftSpeed: _random.nextDouble() * 0.5 + 0.2, // Random low speed
          driftAngle: _random.nextDouble() * 2 * pi,
          color: Colors.primaries[i % Colors.primaries.length],
          size: _random.nextDouble() * 20 + 20, // 20-40 size
        ),
      );
    }
  }

  Future<void> _startAnimationSequence() async {
    // 0.0s - 0.5s: Just drifting (handled by build loop)
    await Future.delayed(const Duration(milliseconds: 600));

    // 0.6s: Magnet Appears
    setState(() => _magnetActive = true);
    _magnetController.forward(); // Scale up logo

    // 0.8s: Trigger Magnetic Snap (Items rush to center)
    await Future.delayed(const Duration(milliseconds: 400));
    _mainController.forward(); // This drives the lerp to center

    // 1.5s: Impact/Navigate
    await Future.delayed(const Duration(milliseconds: 1000));
    _navigateToHome();
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const AuthGate(), // Use AuthGate for status checking
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (_, a, __, child) {
          return FadeTransition(opacity: a, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _magnetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);

    return Scaffold(
      backgroundColor: AppTheme.primaryColor, // Deep Indigo
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _magnetController]),
        builder: (context, child) {
          // 0.0 -> 1.0 progress of "Snapping"
          final snapProgress = _mainController.value;
          final elasticSnap = Curves.elasticIn.transform(snapProgress);

          return Stack(
            children: [
              // 1. Drifting Items
              ..._items.map((item) {
                // Determine current position

                // Drift logic (Circular motion)
                final time = DateTime.now().millisecondsSinceEpoch / 1000;
                final driftOffset = Offset(
                  cos(item.driftAngle + time * item.driftSpeed) * 30,
                  sin(item.driftAngle + time * item.driftSpeed) * 30,
                );

                // Initial Position (relative to center)
                final startOffset =
                    Offset(
                      item.startPos.dx * size.width / 1.5,
                      item.startPos.dy * size.height / 1.5,
                    ) +
                    driftOffset;

                // Target Position (Center)
                const endOffset = Offset.zero;

                // Interpolate based on snap progress
                final currentOffset = Offset.lerp(
                  startOffset,
                  endOffset,
                  elasticSnap,
                )!;

                // Calculate Opacity (Fade out on impact)
                final textOpacity = (1.0 - snapProgress * 1.5).clamp(0.0, 1.0);

                return Positioned(
                  left: center.dx + currentOffset.dx - item.size / 2,
                  top: center.dy + currentOffset.dy - item.size / 2,
                  child: Opacity(
                    opacity: textOpacity,
                    child: Transform.rotate(
                      angle:
                          item.driftAngle +
                          snapProgress * pi * 4, // Spin on verify
                      child: Icon(
                        item.icon,
                        size: item.size,
                        color: item.color.withOpacity(0.8),
                      ),
                    ),
                  ),
                );
              }),

              // 2. The Magnet (Logo)
              if (_magnetActive)
                Center(
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _magnetController,
                      curve: Curves.elasticOut,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/Hanghut.png',
                          width: 150,
                          height: 150,
                          fit: BoxFit.contain,
                        ),
                        if (snapProgress > 0.8)
                          // Reveal text on impact
                          FadeTransition(
                            opacity: _mainController,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                'HANGHUT',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class FloatingItem {
  final IconData icon;
  final Offset startPos;
  final double driftSpeed;
  final double driftAngle;
  final Color color;
  final double size;

  FloatingItem({
    required this.icon,
    required this.startPos,
    required this.driftSpeed,
    required this.driftAngle,
    required this.color,
    required this.size,
  });
}
