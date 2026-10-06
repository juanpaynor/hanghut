import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// A system-made suggestion, asked as a yes/no.
///
/// "☕ Grab coffee at Yardstick Coffee · Sat 10 Oct, 10:00am" — one tap and
/// the hangout exists. There is no poster here because a casual venue has
/// none; the activity emoji carries the identity instead, which keeps the
/// strip short enough to sit over the map.
///
/// Icons used — `Icons.people_outline` — is checked present in base release
/// 11305a4. `Icons.arrow_forward` is NOT, so nothing here uses a chevron.
class HangoutSeedCard extends StatelessWidget {
  final HangoutSeed seed;

  /// "I'm in". The hangout is created server-side; the caller just reports.
  final VoidCallback onYes;

  final VoidCallback onNo;

  /// True while the answer is in flight, so the buttons cannot produce two
  /// conflicting answers.
  final bool busy;

  /// Compact strip for the map, where this competes with the map itself.
  final bool compact;

  const HangoutSeedCard({
    super.key,
    required this.seed,
    required this.onYes,
    required this.onNo,
    this.busy = false,
    this.compact = false,
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
          border: Border.all(color: _accent.withValues(alpha: 0.38)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // Labelled as ours, so a suggestion is never mistaken for a
              // hangout somebody is already hosting.
              seed.status == HangoutSeedStatus.claimed
                  ? 'SOMEONE IS GOING'
                  : 'AN IDEA FOR YOU',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: isDark ? const Color(0xFF8E88FF) : _accent,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: isDark ? 0.24 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    seed.emoji.isNotEmpty ? seed.emoji : '📍',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        seed.headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14.5 : 16,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        seed.whenLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 13,
                            color: isDark ? Colors.white54 : Colors.black38,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              seed.poolLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color:
                                    isDark ? Colors.white60 : Colors.black45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(
                seed.subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onYes,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("I'm in"),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: busy ? null : onNo,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                  ),
                  child: Text(
                    'Not today',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
