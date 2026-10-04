import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// A system-made offer, asked as a yes/no.
///
/// Shows the event's own poster rather than anything generated: it is the
/// actual thing, which is more persuasive than any illustration we could pick
/// — and it is what the user will recognise if they have seen the event
/// anywhere else in the app.
///
/// Icons used — `Icons.place_outlined`, `Icons.people_outline` — are both
/// checked present in base release 11305a4. `Icons.arrow_forward` is NOT, so
/// nothing here uses a trailing chevron.
class HangoutSeedCard extends StatelessWidget {
  final HangoutSeed seed;

  /// "I'm in". The caller decides what happens next, because only the server
  /// knows whether this user hosts or joins.
  final VoidCallback onYes;

  final VoidCallback onNo;

  /// True while a response is in flight, so the buttons cannot produce two
  /// conflicting answers.
  final bool busy;

  /// Compact strip for the map, where the card competes with the map itself.
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
            Row(
              children: [
                if (seed.interestEmoji.isNotEmpty) ...[
                  Text(seed.interestEmoji,
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    // Labelled as ours, so an offer is never mistaken for a
                    // hangout somebody is already hosting.
                    seed.status == HangoutSeedStatus.claimed
                        ? 'SOMEONE IS GOING'
                        : 'GO TOGETHER?',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: isDark ? const Color(0xFF8E88FF) : _accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The event's real poster. Absent on plenty of events, so the
                // layout has to look deliberate without it rather than
                // leaving a grey hole.
                if (seed.coverImageUrl case final url?) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _emojiTile(isDark),
                      placeholder: (_, __) => _emojiTile(isDark),
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
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
                        seed.whereAndWhen,
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
                    'No thanks',
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

  /// Stand-in for a missing or failed poster — the category emoji on a tinted
  /// tile, so the row keeps its shape instead of collapsing.
  Widget _emojiTile(bool isDark) => Container(
        width: 52,
        height: 52,
        color: _accent.withValues(alpha: isDark ? 0.22 : 0.12),
        alignment: Alignment.center,
        child: Text(
          seed.interestEmoji.isNotEmpty ? seed.interestEmoji : '📍',
          style: const TextStyle(fontSize: 22),
        ),
      );
}
