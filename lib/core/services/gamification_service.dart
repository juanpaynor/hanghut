import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';

class GamificationService {
  // Badge Definitions
  static final List<Map<String, dynamic>> _badges = [
    {
      'id': 'early_adopter',
      'name': 'Early Adopter',
      'icon': Icons.rocket_launch,
      'color': Colors.purple,
      'description': 'Joined during the beta phase',
    },
    {
      'id': 'host_level_1',
      'name': 'Rookie Host',
      'icon': Icons.star_border,
      'color': Colors.blue,
      'description': 'Hosted your first table',
    },
    {
      'id': 'host_level_2',
      'name': 'Super Host',
      'icon': Icons.star,
      'color': Colors.amber,
      'description': 'Hosted 5+ tables',
    },
    {
      'id': 'social_butterfly',
      'name': 'Social Butterfly',
      'icon': Icons.groups,
      'color': Colors.pink,
      'description': 'Joined 10+ tables',
    },
    {
      'id': 'verified',
      'name': 'Verified',
      'icon': Icons.verified,
      'color': Color(0xFF00FFD1), // App theme cyan
      'description': 'Identity verified',
    },
  ];

  /// Calculates badges based on user stats
  Future<List<Map<String, dynamic>>> getUserBadges(String userId) async {
    final List<Map<String, dynamic>> userBadges = [];

    try {
      // 1. Fetch User Stats
      final hostedResponse = await SupabaseConfig.client
          .from('tables')
          .select('id')
          .eq('host_id', userId);
      final hostedCount = (hostedResponse as List).length;

      final joinedResponse = await SupabaseConfig.client
          .from('table_participants')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'confirmed');
      final joinedCount = (joinedResponse as List).length;

      final user = await SupabaseConfig.client
          .from('users')
          .select('created_at, trust_score')
          .eq('id', userId)
          .single();

      // 2. Evaluate Rules

      // Rule: Early Adopter (Example: Joined before 2026)
      // For now, we'll just give it to everyone as we are in dev
      userBadges.add(_getBadge('early_adopter'));

      // Rule: Hosts
      if (hostedCount > 0) {
        userBadges.add(_getBadge('host_level_1'));
      }
      if (hostedCount >= 5) {
        userBadges.add(_getBadge('host_level_2'));
      }

      // Rule: Social Butterfly
      if (joinedCount >= 10) {
        userBadges.add(_getBadge('social_butterfly'));
      }

      // Rule: Verified (High trust score)
      final trustScore = user['trust_score'] ?? 0;
      if (trustScore > 80) {
        userBadges.add(_getBadge('verified'));
      }

      return userBadges;
    } catch (e) {
      print('❌ Gamification Error: $e');
      return [];
    }
  }

  Map<String, dynamic> _getBadge(String id) {
    return _badges.firstWhere(
      (b) => b['id'] == id,
      orElse: () => {
        'id': 'unknown',
        'name': 'Unknown',
        'icon': Icons.help_outline,
        'color': Colors.grey,
        'description': '',
      },
    );
  }
}
