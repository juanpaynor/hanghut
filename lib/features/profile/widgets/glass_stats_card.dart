import 'dart:ui';
import 'package:flutter/material.dart';

class GlassStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  const GlassStatsCard({
    super.key,
    required this.stats,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStat('HOSTED', stats['hosted']?.toString() ?? '0'),
              _buildDivider(),
              _buildStat('JOINED', stats['joined']?.toString() ?? '0'),
              _buildDivider(),
              _buildStat(
                'FOLLOWERS',
                stats['followers']?.toString() ?? '0',
                onTap: onFollowersTap,
              ),
              _buildDivider(),
              _buildStat(
                'FOLLOWING',
                stats['following']?.toString() ?? '0',
                onTap: onFollowingTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 30, width: 1, color: Colors.grey.withOpacity(0.3));
  }
}
