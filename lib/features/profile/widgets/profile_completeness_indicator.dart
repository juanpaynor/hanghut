import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class ProfileCompletenessIndicator extends StatelessWidget {
  final Map<String, dynamic> userData;
  final List<Map<String, dynamic>> photos;

  const ProfileCompletenessIndicator({
    super.key,
    required this.userData,
    required this.photos,
  });

  Map<String, dynamic> _calculateCompleteness() {
    int score = 0;
    final List<Map<String, String>> missing = [];

    // Avatar (20%)
    if (photos.isNotEmpty) {
      score += 20;
    } else {
      missing.add({'item': 'Profile Photo', 'tip': 'Add at least one photo'});
    }

    // Bio (20%)
    if (userData['bio'] != null &&
        userData['bio'].toString().trim().isNotEmpty) {
      score += 20;
    } else {
      missing.add({'item': 'Bio', 'tip': 'Tell people about yourself'});
    }

    // Occupation (15%)
    if (userData['occupation'] != null &&
        userData['occupation'].toString().trim().isNotEmpty) {
      score += 15;
    } else {
      missing.add({'item': 'Occupation', 'tip': 'Add your job or profession'});
    }

    // Instagram (10%)
    if (userData['social_instagram'] != null &&
        userData['social_instagram'].toString().trim().isNotEmpty) {
      score += 10;
    } else {
      missing.add({'item': 'Instagram', 'tip': 'Connect your Instagram'});
    }

    // Multiple photos (15%)
    if (photos.length >= 3) {
      score += 15;
    } else if (photos.isNotEmpty) {
      missing.add({
        'item': 'More Photos',
        'tip': 'Add ${3 - photos.length} more photos',
      });
    }

    // Tags (20%)
    final tags = userData['tags'] as List?;
    if (tags != null && tags.length >= 3) {
      score += 20;
    } else {
      final tagsNeeded = tags == null ? 3 : (3 - tags.length);
      missing.add({'item': 'Interest Tags', 'tip': 'Add $tagsNeeded tags'});
    }

    return {'score': score, 'missing': missing};
  }

  @override
  Widget build(BuildContext context) {
    final completeness = _calculateCompleteness();
    final score = completeness['score'] as int;
    final missing = completeness['missing'] as List<Map<String, String>>;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (score == 100) {
      // Profile complete - show achievement badge
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.accentColor.withOpacity(0.2), Colors.transparent],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: AppTheme.accentColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile Complete! 🎉',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Your profile is looking great!',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Profile incomplete - show progress
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Title
                Text(
                  'Complete Your Profile',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add these items to reach 100%',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Missing items
                ...missing.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['item']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                item['tip']!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it!'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            // Progress circle
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation(
                      AppTheme.accentColor,
                    ),
                    strokeWidth: 4,
                  ),
                  Text(
                    '$score%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Complete Your Profile',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${missing.length} items remaining',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
