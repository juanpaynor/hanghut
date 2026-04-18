import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';

/// Animated gradient progress bar for the create-hangout wizard.
class HangoutProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const HangoutProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (currentStep + 1) / totalSteps;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Step label
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Step ${currentStep + 1} of $totalSteps',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Bar
        Container(
          height: 4,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200],
            borderRadius: BorderRadius.circular(2),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth * fraction,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFF8B9FFF)],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
