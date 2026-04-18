import 'package:flutter/material.dart';

import 'package:bitemates/core/theme/app_theme.dart';
import 'create_trip_flow.dart';

/// Step 2: Travel style + Interests
class TripStepStyleInterests extends StatelessWidget {
  final CreateTripFlowState flow;
  const TripStepStyleInterests({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.luggage_rounded,
                size: 40,
                color: Color(0xFFFFC107),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'How do you travel?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'This helps us match you with like-minded travelers',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: onSurface.withOpacity(0.5)),
            ),
          ),
          const SizedBox(height: 28),

          // ── Travel Style ──
          Text(
            'Travel Style',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          ...flow.travelStyles.map((style) {
            final isSelected = flow.travelStyle == style['value'];
            return GestureDetector(
              onTap: () {
                flow.travelStyle = style['value'] as String;
                flow.rebuild();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withOpacity(0.08)
                      : surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor.withOpacity(0.15)
                            : (isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.grey.withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        style['icon'] as IconData,
                        size: 22,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            style['label'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            style['description'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          // ── Interests ──
          Text(
            'What are you into?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick as many as you like',
            style: TextStyle(fontSize: 12, color: onSurface.withOpacity(0.4)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: flow.interests.map((interest) {
              final isSelected = flow.selectedInterests.contains(
                interest['value'],
              );
              return GestureDetector(
                onTap: () {
                  if (isSelected) {
                    flow.selectedInterests.remove(interest['value']);
                  } else {
                    flow.selectedInterests.add(interest['value']!);
                  }
                  flow.rebuild();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withOpacity(0.12)
                        : surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.withOpacity(0.2)),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    interest['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected ? AppTheme.primaryColor : onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
