import 'package:flutter/material.dart';

import 'package:bitemates/core/theme/app_theme.dart';
import 'create_trip_flow.dart';

/// Step 3: Goals + Optional description
class TripStepGoals extends StatelessWidget {
  final CreateTripFlowState flow;
  const TripStepGoals({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
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
                  color: Colors.green.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  size: 40,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'What\'s the goal?',
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
                'Pick at least one so we can find the right people',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: onSurface.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Goals ──
            ...flow.goals.map((goal) {
              final isSelected = flow.selectedGoals.contains(goal['value']);
              return GestureDetector(
                onTap: () {
                  if (isSelected) {
                    flow.selectedGoals.remove(goal['value']);
                  } else {
                    flow.selectedGoals.add(goal['value']!);
                  }
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
                      Expanded(
                        child: Text(
                          goal['label']!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: onSurface,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : (isDark
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.grey.withOpacity(0.3)),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // ── Description ──
            Text(
              'Anything else? (optional)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: flow.descriptionController,
              maxLines: 4,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText:
                    'Share more about your trip plans, what you\'re excited about...',
                hintStyle: TextStyle(color: onSurface.withOpacity(0.35)),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
