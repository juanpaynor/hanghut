import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';

/// The standing prompt on the map — one line, a button, and a dismiss.
///
/// Distinct from `HangoutNudgeCard` (the tall version used in empty states)
/// because the map is not an empty screen: it already carries filters, map
/// controls, the nav bar and the FAB. A full card here would cover the thing
/// the user came to look at, so this is deliberately a single floating strip.
///
/// Distinct from `HangoutNudgePrompt` (the modal) in persistence rather than
/// content: the modal is rationed to three appearances ever because it
/// interrupts, while this is always available to anyone who wants it and
/// costs nothing to ignore.
///
/// Icons used — `Icons.add`, `Icons.close` — are both checked present in base
/// release 11305a4. `Icons.arrow_forward` is NOT in that release and would
/// render as "?" through a Shorebird patch.
class HangoutNudgeBanner extends StatelessWidget {
  final HangoutNudge nudge;
  final VoidCallback onStart;
  final VoidCallback onDismiss;

  const HangoutNudgeBanner({
    super.key,
    required this.nudge,
    required this.onStart,
    required this.onDismiss,
  });

  static const Color _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C21) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _accent.withValues(alpha: 0.35)),
          // The map behind this is busy and varies in brightness, so the
          // strip needs its own elevation to stay readable over any tile.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: isDark ? 0.24 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: nudge.interestEmoji.isNotEmpty
                    ? Text(
                        nudge.interestEmoji,
                        style: const TextStyle(fontSize: 17),
                      )
                    : Text(
                        '${nudge.nearbyCount}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFF8E88FF) : _accent,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${nudge.nearbyCount} near you like '
                    '${nudge.interestLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Nobody has made a plan yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Icon-only: the strip has to fit a narrow phone alongside the
            // count and the dismiss, and "Start" with a label pushed the
            // headline into an ellipsis at 360dp.
            SizedBox(
              width: 38,
              height: 38,
              child: FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(38, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.add, size: 21),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              icon: Icon(
                Icons.close,
                size: 17,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
