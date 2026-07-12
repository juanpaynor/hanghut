import 'package:flutter/material.dart';

/// A curated cover gradient for groups that have no uploaded cover image.
///
/// Themes are keyed to the group's category so the look is *meaningful*
/// (food = warm, music = purple, travel = sky) rather than a flat default.
/// This applies retroactively to every coverless group — no schema, no stored
/// choice — so groups look intentional the moment they're created.
class GroupCover {
  final List<Color> gradient;

  /// A solid accent (the gradient's darker end) for tinting icons/avatars so
  /// they sit cohesively against the same theme.
  final Color accent;

  const GroupCover(this.gradient, this.accent);

  /// Top-left → bottom-right linear gradient for cover surfaces.
  LinearGradient get linear => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradient,
      );

  static const Map<String, GroupCover> _byCategory = {
    'food': GroupCover([Color(0xFFFF8A65), Color(0xFFE64A19)], Color(0xFFE64A19)),
    'nightlife':
        GroupCover([Color(0xFF7C4DFF), Color(0xFF3F1D8A)], Color(0xFF512DA8)),
    'travel':
        GroupCover([Color(0xFF4FC3F7), Color(0xFF0288D1)], Color(0xFF0277BD)),
    'fitness':
        GroupCover([Color(0xFF4DD0A1), Color(0xFF00897B)], Color(0xFF00796B)),
    'outdoors':
        GroupCover([Color(0xFF66BB6A), Color(0xFF2E7D32)], Color(0xFF2E7D32)),
    'gaming':
        GroupCover([Color(0xFF5C6BC0), Color(0xFF7B1FA2)], Color(0xFF6A1B9A)),
    'arts': GroupCover([Color(0xFFF06292), Color(0xFF8E24AA)], Color(0xFF8E24AA)),
    'music':
        GroupCover([Color(0xFF9C27B0), Color(0xFFE91E63)], Color(0xFF8E24AA)),
    'professional':
        GroupCover([Color(0xFF546E7A), Color(0xFF37474F)], Color(0xFF455A64)),
    'other':
        GroupCover([Color(0xFF26C6DA), Color(0xFF00838F)], Color(0xFF00838F)),
  };

  /// Fallback palette for any unrecognised category — picked deterministically
  /// so the same group always renders the same way.
  static const List<GroupCover> _fallbacks = [
    GroupCover([Color(0xFF26C6DA), Color(0xFF00838F)], Color(0xFF00838F)),
    GroupCover([Color(0xFF7C4DFF), Color(0xFF3F1D8A)], Color(0xFF512DA8)),
    GroupCover([Color(0xFFFF8A65), Color(0xFFE64A19)], Color(0xFFE64A19)),
    GroupCover([Color(0xFF4DD0A1), Color(0xFF00897B)], Color(0xFF00796B)),
  ];

  /// Resolve a cover theme for a group. Prefers a category match; otherwise
  /// hashes [seed] (group id or name) for a stable pick.
  static GroupCover forGroup({String? category, String? seed}) {
    final key = category?.toLowerCase().trim();
    final match = key != null ? _byCategory[key] : null;
    if (match != null) return match;

    final s = (seed == null || seed.isEmpty) ? (key ?? 'other') : seed;
    final idx = s.codeUnits.fold<int>(0, (a, b) => a + b) % _fallbacks.length;
    return _fallbacks[idx];
  }
}
