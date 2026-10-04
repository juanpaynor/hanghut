import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';

/// The card that turns "No open hangouts right now" into a reason to make one.
///
/// Renders [SizedBox.shrink] when there is no nudge, so every call site can
/// mount it unconditionally and the screen is unchanged for users the RPC has
/// nothing to say about (no location, no taste signal, nobody nearby, or
/// already in an upcoming hangout).
///
/// Every icon here is checked present in base release 11305a4 — `Icons.add`,
/// `Icons.people_outline`, `Icons.auto_awesome`. A Shorebird patch ships Dart
/// only, so an icon absent from the release renders as "?".
/// `Icons.arrow_forward` is NOT in the release; that is why the button has no
/// trailing chevron.
class HangoutNudgeCard extends StatelessWidget {
  final HangoutNudge nudge;
  final VoidCallback onStart;

  /// Tighter padding for the empty state, where the card is the only thing on
  /// screen and does not need to compete with a grid below it.
  final bool compact;

  const HangoutNudgeCard({
    super.key,
    required this.nudge,
    required this.onStart,
    this.compact = false,
  });

  /// The app's accent, matching the vibe chips in `hangouts_tab.dart`.
  static const Color _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 0 : 12, 16, compact ? 0 : 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // A tint rather than a filled block: this sits above a grid of cards
          // and must read as a prompt, not as another hangout.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withValues(alpha: isDark ? 0.22 : 0.12),
              _accent.withValues(alpha: isDark ? 0.08 : 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _accent.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 18,
                  color: isDark ? const Color(0xFF8E88FF) : _accent,
                ),
                const SizedBox(width: 6),
                // The emoji comes from event_categories, so it is whatever web
                // set for the category and may be empty.
                if (nudge.interestEmoji.isNotEmpty) ...[
                  Text(
                    nudge.interestEmoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    nudge.interestLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: isDark ? const Color(0xFF8E88FF) : _accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              nudge.headline,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.25,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              nudge.subtitle,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.add, size: 20),
                label: Text(nudge.ctaLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
