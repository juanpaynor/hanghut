import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class StatsExplainerModal extends StatelessWidget {
  final Map<String, double> stats;
  final Map<String, dynamic> userData;

  const StatsExplainerModal({
    super.key,
    required this.stats,
    required this.userData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(
                          Icons.help_outline,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Stats Breakdown',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Stats breakdown
                    _buildStatItem(
                      context,
                      'Social',
                      stats['Social'] ?? 0,
                      'Based on tables you\'ve hosted',
                      'Host more tables to increase',
                      Icons.groups,
                      Colors.purple,
                    ),
                    const SizedBox(height: 16),

                    _buildStatItem(
                      context,
                      'Active',
                      stats['Active'] ?? 0,
                      'Based on tables you\'ve joined',
                      'Join more tables to level up',
                      Icons.local_fire_department,
                      Colors.orange,
                    ),
                    const SizedBox(height: 16),

                    _buildStatItem(
                      context,
                      'Karma',
                      stats['Karma'] ?? 0,
                      'Your trust score from the community',
                      'Be a great tablemate to improve',
                      Icons.favorite,
                      Colors.red,
                    ),
                    const SizedBox(height: 16),

                    _buildStatItem(
                      context,
                      'Explore',
                      stats['Explore'] ?? 0,
                      'Based on your photo gallery',
                      'Add more photos to boost',
                      Icons.explore,
                      Colors.blue,
                    ),
                    const SizedBox(height: 16),

                    _buildStatItem(
                      context,
                      'Taste',
                      stats['Taste'] ?? 0,
                      'Your food preference diversity',
                      'Try different cuisines',
                      Icons.restaurant,
                      Colors.green,
                    ),

                    const SizedBox(height: 24),

                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it!'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String name,
    double value,
    String description,
    String howToImprove,
    IconData icon,
    Color color,
  ) {
    final percentage = (value * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        howToImprove,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
