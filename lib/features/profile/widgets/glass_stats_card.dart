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
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0.75),
                    ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.7),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildStatItem(
                context,
                value: stats['hosted']?.toString() ?? '0',
                label: 'Hosted',
                isDark: isDark,
              ),
              _buildStatItem(
                context,
                value: stats['joined']?.toString() ?? '0',
                label: 'Joined',
                isDark: isDark,
              ),
              _buildStatItem(
                context,
                value: stats['followers']?.toString() ?? '0',
                label: 'Followers',
                isDark: isDark,
                onTap: onFollowersTap,
              ),
              _buildStatItem(
                context,
                value: stats['following']?.toString() ?? '0',
                label: 'Following',
                isDark: isDark,
                onTap: onFollowingTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String value,
    required String label,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Value
             Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 4),
            // Label
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
