import 'package:flutter/material.dart' hide Badge;
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/utils/badge_helper.dart';

class BadgeCard extends StatelessWidget {
  final Badge badge;
  final bool isEarned;
  final VoidCallback? onTap;

  const BadgeCard({
    super.key,
    required this.badge,
    this.isEarned = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = BadgeHelper.getColor(badge.tier);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEarned
                  ? badgeColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              border: Border.all(
                color: isEarned ? badgeColor : Colors.grey.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: isEarned
                  ? [
                      BoxShadow(
                        color: badgeColor.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              BadgeHelper.getIcon(badge.iconKey),
              size: 32,
              color: isEarned ? badgeColor : Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              badge.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: isEarned ? FontWeight.bold : FontWeight.normal,
                color: isEarned ? null : Colors.grey,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
