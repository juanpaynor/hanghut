import 'package:flutter/material.dart' hide Badge;
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/utils/badge_helper.dart';
import 'package:bitemates/features/gamification/widgets/badge_card.dart';

class BadgeList extends StatelessWidget {
  final List<Badge> allBadges;
  final Set<String> earnedBadgeIds;

  const BadgeList({
    super.key,
    required this.allBadges,
    required this.earnedBadgeIds,
  });

  @override
  Widget build(BuildContext context) {
    if (allBadges.isEmpty) {
      return const Center(child: Text("No badges available yet."));
    }

    return SizedBox(
      height: 120, // ample height for circle + text
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allBadges.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final badge = allBadges[index];
          final isEarned = earnedBadgeIds.contains(badge.id);
          return BadgeCard(
            badge: badge,
            isEarned: isEarned,
            onTap: () {
              _showBadgeDetails(context, badge, isEarned);
            },
          );
        },
      ),
    );
  }

  void _showBadgeDetails(BuildContext context, Badge badge, bool isEarned) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              BadgeHelper.getIcon(badge.iconKey),
              color: BadgeHelper.getColor(badge.tier),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(badge.name)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(badge.description),
            const SizedBox(height: 16),
            if (isEarned)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Earned!",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              const Row(
                children: [
                  Icon(Icons.lock, color: Colors.grey, size: 20),
                  SizedBox(width: 8),
                  Text("Locked", style: TextStyle(color: Colors.grey)),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              "Tier: ${badge.tier}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
