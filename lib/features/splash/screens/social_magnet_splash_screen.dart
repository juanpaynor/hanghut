import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitemates/main.dart'; // Import for AuthGate
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class SocialMagnetSplashScreen extends StatefulWidget {
  const SocialMagnetSplashScreen({super.key});

  @override
  State<SocialMagnetSplashScreen> createState() =>
      _SocialMagnetSplashScreenState();
}

class _SocialMagnetSplashScreenState extends State<SocialMagnetSplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after a delay (GIF duration + buffer)
    // Assuming GIF is short, giving it 3.5 seconds total
    Future.delayed(const Duration(milliseconds: 3500), () {
      _navigateToHome();
    });
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // App Primary Color (Indigo)
    const primaryColor = Color(0xFF6B7FFF);

    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated GIF
            Image.asset(
              'assets/images/logo_animated.gif',
              width: 280, // A tad bigger
              height: 280,
            ),
            const SizedBox(height: 10),

            // "Hanghut" Letter-by-Letter Animation
            Row(
              mainAxisSize: MainAxisSize.min,
              children: "Hanghut".split('').asMap().entries.map((entry) {
                final index = entry.key;
                final letter = entry.value;

                // Staggered Animation: Slide up + Fade in + slight bounce
                return Text(
                      letter,
                      style: GoogleFonts.inter(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.5,
                      ),
                    )
                    .animate()
                    .fade(
                      duration: 400.ms,
                      delay: (400 + (index * 100)).ms,
                    ) // Start after GIF starts
                    .moveY(
                      begin: 20,
                      end: 0,
                      duration: 500.ms,
                      curve: Curves.easeOutBack,
                    );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
