import 'package:flutter/material.dart';

/// Shared styling for partner badges — tier colours + rarity from holder_count.
///
/// Lives in its own file so every badge surface (case, inline stamp, share card,
/// earn overlay) can read it without importing one another. That keeps the
/// share card, which the case links out to, from importing the case back.
class CreatorBadgeStyle {
  static const tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFFFD700),
    'platinum': Color(0xFFE5E4E2),
    'diamond': Color(0xFFB9F2FF),
    'special': Color(0xFF8E88FF),
  };

  static Color tierColor(String tier) =>
      tierColors[tier.toLowerCase()] ?? const Color(0xFF8E88FF);

  /// Rarity from how many people hold the badge. Always sourced from the
  /// server's `holder_count` — the client never aggregates `user_creator_badges`
  /// itself (team_comms #243).
  static ({String label, Color color}) rarity(int holderCount) {
    if (holderCount > 0 && holderCount <= 10) {
      return (label: 'Legendary', color: const Color(0xFFFFB020));
    } else if (holderCount <= 50) {
      return (label: 'Rare', color: const Color(0xFF9F7AEA));
    } else if (holderCount <= 250) {
      return (label: 'Uncommon', color: const Color(0xFF4299E1));
    }
    return (label: 'Common', color: const Color(0xFF8A8A99));
  }

  static String holderLabel(int n) {
    if (n <= 0) return 'Be the first to earn this';
    if (n == 1) return 'Held by 1 person';
    return 'Held by ${_compact(n)} people';
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
