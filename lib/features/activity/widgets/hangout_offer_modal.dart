import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/klipy_service.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// The full-size version of an offer, with a GIF.
///
/// The map card is a strip that has to share space with the map; this is the
/// moment the offer gets to be fun. The GIF is the reaction layer — the
/// event's own poster sits underneath it as the credible, factual part.
///
/// The GIF is chosen **deterministically from the seed id**, so everyone
/// offered the same event sees the same one and it does not reshuffle on
/// every rebuild. That matters for a shared social object: two people
/// comparing the same offer should be looking at the same thing.
///
/// Klipy is a metered third-party API, so this fetches **once per modal**,
/// never in a list, and fails soft to the poster alone. See
/// feedback_no_metered_features — no cost is quoted here, and the call volume
/// is one per offer shown.
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
  /// The query is the category label rather than the event title: event
  /// titles are proper nouns ("SANSARI", "GB LABRADOR AND THE INGLISHEROS")
  /// and return nothing useful, while "stand-up comedy" reliably returns
  /// something that reads as the right mood.
  Future<void> _loadGif() async {
    try {
      final results = await KlipyService().searchGifs(
        _queryFor(widget.seed),
        limit: 12,
      );
      if (!mounted || results.isEmpty) return;
      // Deterministic per offer: the same seed always yields the same GIF.
      final index = widget.seed.seedId.hashCode.abs() % results.length;
      final url = KlipyService().getGifUrl(results[index]);
      if (url.isNotEmpty) setState(() => _gifUrl = url);
    } catch (_) {
      // Fails soft: the poster alone is a complete card.
    }
  }

  static String _queryFor(HangoutSeed seed) {
    final label = seed.interestLabel.toLowerCase();
    // A couple of the category labels make poor search terms on their own.
    return switch (seed.category) {
      'games_social' => 'board game night',
      'markets_popups' => 'shopping market',
      'community' => 'friends hanging out',
      'workshops_classes' => 'craft workshop',
      _ => label,
    };
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
                      : 'GO TOGETHER?',
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
                  seed.whereAndWhen,
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
          // The credible layer: the event's own poster, blurred behind.
          if (seed.coverImageUrl case final cover?)
            CachedNetworkImage(
              imageUrl: cover,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: fallbackTint),
              placeholder: (_, __) => Container(color: fallbackTint),
            )
          else
            Container(color: fallbackTint),

          // The fun layer. Absent until it loads, and absent for good if
          // Klipy fails — the poster alone is a complete hero.
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

          if (seed.interestEmoji.isNotEmpty)
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
                  '${seed.interestEmoji} ${seed.interestLabel}',
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
