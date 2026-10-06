import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/klipy_service.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// The full-size version of a suggestion, with a GIF.
///
/// The map card is a strip that shares space with the map; this is where the
/// suggestion gets to be fun. The GIF sets the mood for the activity — the
/// plain facts (what, where, when) sit underneath it.
///
/// The GIF is picked **deterministically from the seed id**, so everyone
/// offered the same plan sees the same one and it does not reshuffle on every
/// rebuild. For a shared social object that matters: two people comparing the
/// same suggestion should be looking at the same thing.
///
/// Klipy is a metered third-party API, so this fetches **once per modal**,
/// never in a list, and fails soft to a plain tinted hero. See
/// feedback_no_metered_features — no cost is quoted here, and the call volume
/// is one request per suggestion actually shown.
class HangoutOfferModal extends StatefulWidget {
  final HangoutSeed seed;

  /// Called after the modal closes, so the create flow is not pushed behind
  /// a dialog.
  final VoidCallback onYes;
  final VoidCallback onNo;

  const HangoutOfferModal({
    super.key,
    required this.seed,
    required this.onYes,
    required this.onNo,
  });

  /// Shows the modal. Returns true if the user said yes.
  static Future<bool> show(
    BuildContext context, {
    required HangoutSeed seed,
  }) async {
    var saidYes = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HangoutOfferModal(
        seed: seed,
        onYes: () => saidYes = true,
        onNo: () {},
      ),
    );
    return saidYes;
  }

  @override
  State<HangoutOfferModal> createState() => _HangoutOfferModalState();
}

class _HangoutOfferModalState extends State<HangoutOfferModal> {
  static const Color _accent = Color(0xFF6C63FF);

  String? _gifUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadGif();
  }

  /// One search, one pick, no retries.
  ///
  /// The query comes from the activity catalogue, not the venue name: "coffee
  /// with friends" reliably returns the right mood, while "Yardstick Coffee"
  /// returns nothing.
  Future<void> _loadGif() async {
    try {
      final q = widget.seed.gifQuery;
      if (q.isEmpty) return;
      final results = await KlipyService().searchGifs(q, limit: 12);
      if (!mounted || results.isEmpty) return;
      // Deterministic per offer: the same seed always yields the same GIF.
      final index = widget.seed.seedId.hashCode.abs() % results.length;
      final url = KlipyService().getGifUrl(results[index]);
      if (url.isNotEmpty) setState(() => _gifUrl = url);
    } catch (_) {
      // Fails soft: the poster alone is a complete card.
    }
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.seed;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C21) : Colors.white;

    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seed.status == HangoutSeedStatus.claimed
                      ? 'SOMEONE IS GOING'
                      : 'AN IDEA FOR YOU',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: isDark ? const Color(0xFF8E88FF) : _accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  seed.headline,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  seed.whenLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 15,
                      color: isDark ? Colors.white54 : Colors.black38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        seed.poolLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  seed.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _busy = true);
                            Navigator.of(context).pop();
                            widget.onYes();
                          },
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
                    child: const Text("I'm in"),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onNo();
                          },
                    child: Text(
                      'No thanks',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// GIF over the event poster.
  ///
  /// Fixed height so the dialog does not resize when the GIF arrives — a
  /// modal that jumps after opening reads as broken.
  Widget _hero(bool isDark) {
    final seed = widget.seed;
    final fallbackTint = _accent.withValues(alpha: isDark ? 0.24 : 0.12);

    return SizedBox(
      height: 168,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // No poster: a casual venue has none. The tint is the resting
          // state and stays visible if Klipy fails or is slow.
          Container(color: fallbackTint),

          // The fun layer. Absent until it loads, and absent for good if the
          // search fails — the hero is complete without it.
          if (_gifUrl case final gif?)
            CachedNetworkImage(
              imageUrl: gif,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
              placeholder: (_, __) => const SizedBox.shrink(),
            ),

          // Keeps the emoji badge legible over any GIF.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          if (seed.emoji.isNotEmpty)
            Positioned(
              top: 12,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${seed.emoji} ${seed.activityTitle}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
