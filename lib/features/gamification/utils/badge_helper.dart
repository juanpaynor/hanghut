import 'package:flutter/material.dart';

class BadgeHelper {
  static IconData getIcon(String iconKey) {
    switch (iconKey) {
      // Hosting
      case 'star':
        return Icons.star_outline_rounded;
      case 'star_filled':
        return Icons.star_rounded;
      case 'crown':
        return Icons.workspace_premium_rounded;
      // Social
      case 'user':
        return Icons.person_rounded;
      case 'users':
        return Icons.people_rounded;
      case 'party_popper':
        return Icons.celebration_rounded;
      // Meetup
      case 'handshake':
        return Icons.handshake_rounded;
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'explore':
        return Icons.explore_rounded;
      case 'people':
        return Icons.group_rounded;
      // Verified
      case 'verified_user':
        return Icons.verified_rounded;
      // Legacy keys
      case 'first_event':
        return Icons.flight_takeoff_rounded;
      case 'host_master':
        return Icons.local_activity_rounded;
      case 'social_butterfly':
        return Icons.people_rounded;
      case 'early_bird':
        return Icons.wb_sunny_rounded;
      case 'top_host':
        return Icons.star_rounded;
      case 'connector':
        return Icons.hub_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
  }

  static Color getColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      case 'special':
        return const Color(0xFF6366F1);
      default:
        return Colors.blue;
    }
  }

  static String xpLabel(int xp) {
    if (xp <= 0) return '';
    return '+$xp XP';
  }
}
