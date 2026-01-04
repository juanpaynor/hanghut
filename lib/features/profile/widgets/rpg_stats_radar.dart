import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class RpgStatsRadar extends StatelessWidget {
  final Map<String, double> stats;
  final Color? color;

  const RpgStatsRadar({super.key, required this.stats, this.color});

  @override
  Widget build(BuildContext context) {
    // Expected keys: Social, Taste, Active, Karma, Explore
    // We expect values 0.0 to 1.0 (normalized)
    final keys = ['Social', 'Taste', 'Active', 'Karma', 'Explore'];

    // Default data if missing
    final dataValues = keys.map((k) => stats[k] ?? 0.5).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = color ?? Theme.of(context).primaryColor;
    final gridColor = isDark ? Colors.white24 : Colors.black12;
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return AspectRatio(
      aspectRatio: 1.3,
      child: RadarChart(
        RadarChartData(
          radarTouchData: RadarTouchData(enabled: false), // Static for now
          dataSets: [
            RadarDataSet(
              fillColor: primaryColor.withOpacity(0.4),
              borderColor: primaryColor,
              entryRadius: 3,
              dataEntries: dataValues.map((v) => RadarEntry(value: v)).toList(),
              borderWidth: 2,
            ),
          ],
          radarBackgroundColor: Colors.transparent,
          borderData: FlBorderData(show: false),
          radarBorderData: const BorderSide(color: Colors.transparent),
          titlePositionPercentageOffset: 0.2,
          titleTextStyle: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter', // Assuming App Font
          ),
          getTitle: (index, angle) {
            if (index >= keys.length) return RadarChartTitle(text: '');
            return RadarChartTitle(text: keys[index]);
          },
          tickCount: 1,
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          tickBorderData: BorderSide(color: gridColor),
          gridBorderData: BorderSide(color: gridColor, width: 1),
        ),
      ),
    );
  }
}
