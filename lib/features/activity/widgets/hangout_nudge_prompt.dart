import 'package:flutter/material.dart';
import 'package:bitemates/core/services/hangout_nudge_service.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';

/// The modal that asks, on the landing screen, whether you want to start
/// something.
///
/// This exists because the card alone was not enough: it lived on the
/// Hangouts sub-tab of Explore and in the My Hangouts empty state, neither of
/// which a user sees unless they go looking. 87% of the user base has never
/// been told a hangout exists, and the map is where they actually land.
///
/// It is an interruption, so it is rationed: at most
/// [HangoutNudgeService.maxShows] times ever, no more often than
/// [HangoutNudgeService.cooldown], never for a user who already has an
/// upcoming hangout (the RPC suppresses those), and never without a real
/// number to show. "Not now" stops it permanently.
///
/// Every icon is checked present in base release 11305a4 — `Icons.add`,
/// `Icons.people_outline`. `Icons.arrow_forward` is NOT, and must not be used
/// here: a Shorebird patch ships Dart only, so it would render as "?".
class HangoutNudgePrompt extends StatelessWidget {
  final HangoutNudge nudge;

  /// Called when the user accepts. The caller owns navigation — this widget
  /// pops itself first so the create flow does not open behind a dialog.
  final VoidCallback onStart;

  const HangoutNudgePrompt({
    super.key,
    required this.nudge,
    required this.onStart,
  });

  static const Color _accent = Color(0xFF6C63FF);

  /// Shows the prompt if it is due, and records that it was shown.
  ///
  /// Returns true if it was actually displayed, so a caller running a queue
  /// knows whether it consumed the user's attention.
  ///
  /// The gate is re-checked here rather than trusted from the call site: this
  /// is the only place that can guarantee the cooldown is written whenever
  /// the dialog is shown, including when the user dismisses by tapping the
  /// barrier, which runs no callback at all.
  static Future<bool> maybeShow(
    BuildContext context, {
    required VoidCallback onStart,
  }) async {
    final service = HangoutNudgeService();
    if (!await service.shouldShowPrompt()) return false;
    final nudge = await service.fetch();
    if (nudge == null) return false;

    // Recorded before the last mounted check so the cooldown is written even
    // if the screen goes away between here and the dialog — the alternative
    // is a prompt that re-fires on the next launch.
    await service.markPromptShown();
    if (!context.mounted) return false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HangoutNudgePrompt(nudge: nudge, onStart: onStart),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C21) : Colors.white;

    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: isDark ? 0.22 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: nudge.interestEmoji.isNotEmpty
                    // The emoji is whatever web set on the category, so it may
                    // be absent — fall back to an icon rather than a gap.
                    ? Text(
                        nudge.interestEmoji,
                        style: const TextStyle(fontSize: 26),
                      )
                    : Icon(
                        Icons.people_outline,
                        size: 28,
                        color: isDark ? const Color(0xFF8E88FF) : _accent,
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              nudge.headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Nobody has made a plan yet. Pick a spot and a time and we\'ll '
              'tell the people nearby.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Pop first: the create flow is a full route and would
                  // otherwise push behind this dialog.
                  Navigator.of(context).pop();
                  onStart();
                },
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Start something'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                // An explicit no is final. Leaving it on the cooldown would
                // bring it back twice more to someone who already declined.
                HangoutNudgeService().suppressPromptPermanently();
                Navigator.of(context).pop();
              },
              child: Text(
                'Not now',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
