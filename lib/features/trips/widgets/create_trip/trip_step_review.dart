import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bitemates/core/theme/app_theme.dart';
import 'create_trip_flow.dart';

/// Step 4: Review everything before submitting
class TripStepReview extends StatelessWidget {
  final CreateTripFlowState flow;
  const TripStepReview({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;

    final destination = flow.cityController.text.trim();
    final dateRange = flow.startDate != null && flow.endDate != null
        ? '${DateFormat('MMM d').format(flow.startDate!)} - ${DateFormat('MMM d, yyyy').format(flow.endDate!)}'
        : 'Not set';
    final days = flow.startDate != null && flow.endDate != null
        ? flow.endDate!.difference(flow.startDate!).inDays + 1
        : 0;

    final styleName =
        flow.travelStyles.firstWhere(
              (s) => s['value'] == flow.travelStyle,
            )['label']
            as String;

    final interestLabels = flow.interests
        .where((i) => flow.selectedInterests.contains(i['value']))
        .map((i) => i['label']!)
        .toList();

    final goalLabels = flow.goals
        .where((g) => flow.selectedGoals.contains(g['value']))
        .map((g) => g['label']!)
        .toList();

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
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fact_check_rounded,
                size: 40,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Looking good! 🎉',
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
              'Review your trip before publishing',
              style: TextStyle(fontSize: 14, color: onSurface.withOpacity(0.5)),
            ),
          ),
          const SizedBox(height: 28),

          // ── Summary card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey.withOpacity(0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Destination
                _ReviewRow(
                  icon: Icons.flight_takeoff_rounded,
                  iconColor: AppTheme.primaryColor,
                  label: 'Destination',
                  value: destination.isNotEmpty ? destination : 'Not set',
                  onSurface: onSurface,
                ),
                _divider(isDark),

                // Dates
                _ReviewRow(
                  icon: Icons.calendar_month_rounded,
                  iconColor: Colors.orange,
                  label: 'Dates',
                  value: days > 0 ? '$dateRange ($days days)' : dateRange,
                  onSurface: onSurface,
                ),
                _divider(isDark),

                // Travel style
                _ReviewRow(
                  icon: Icons.luggage_rounded,
                  iconColor: const Color(0xFFFFC107),
                  label: 'Style',
                  value: styleName,
                  onSurface: onSurface,
                ),
                _divider(isDark),

                // Interests
                _ReviewRow(
                  icon: Icons.interests_rounded,
                  iconColor: Colors.pink,
                  label: 'Interests',
                  value: interestLabels.isNotEmpty
                      ? interestLabels.join(', ')
                      : 'None selected',
                  onSurface: onSurface,
                ),
                _divider(isDark),

                // Goals
                _ReviewRow(
                  icon: Icons.flag_rounded,
                  iconColor: Colors.green,
                  label: 'Goals',
                  value: goalLabels.isNotEmpty
                      ? goalLabels.join(', ')
                      : 'None selected',
                  onSurface: onSurface,
                ),

                // Description (if any)
                if (flow.descriptionController.text.trim().isNotEmpty) ...[
                  _divider(isDark),
                  _ReviewRow(
                    icon: Icons.notes_rounded,
                    iconColor: Colors.blue,
                    label: 'Notes',
                    value: flow.descriptionController.text.trim(),
                    onSurface: onSurface,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
          Center(
            child: Text(
              'Tap "Plan Trip" to publish and start matching!',
              style: TextStyle(
                fontSize: 13,
                color: onSurface.withOpacity(0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(
      height: 1,
      color: isDark
          ? Colors.white.withOpacity(0.06)
          : Colors.grey.withOpacity(0.15),
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color onSurface;

  const _ReviewRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withOpacity(0.45),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: onSurface,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
