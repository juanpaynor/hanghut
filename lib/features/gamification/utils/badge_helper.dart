import 'package:flutter/material.dart';

class BadgeHelper {
  static IconData getIcon(String iconKey) {
    switch (iconKey) {
      case 'first_event':
        return Icons.flight_takeoff;
      case 'host_master':
        return Icons.local_activity;
      case 'social_butterfly':
        return Icons.people;
      case 'early_bird':
        return Icons.wb_sunny;
      case 'top_host':
        return Icons.star;
      case 'connector':
        return Icons.hub;
      default:
        return Icons.emoji_events;
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
      default:
        return Colors.blue;
    }
  }
}
