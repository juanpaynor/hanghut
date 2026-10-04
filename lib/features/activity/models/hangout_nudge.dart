/// The reason to start a hangout, in one sentence.
///
/// The Hangouts tab's problem was never that it looked bad — it was that it
/// had nothing to say. With 5 live hangouts in the whole app, nearly every
/// user saw "No open hangouts right now", which is a dead end: true, and
/// useless. Nothing on the screen suggested the user could change it.
///
/// This type carries the one fact that reframes that emptiness as an
/// opportunity — "22 people near you are into Nightlife" — sourced from
/// `get_hangout_nudge()`. Measured 2026-10-05: of 154 users with taste and a
/// location, 123 have a pool of 3+ and 116 have 10+, averaging 23 people.
///
/// It deliberately carries **no identities**. The RPC returns a count and a
/// category and provides no way to ask who the people are; individuals become
/// visible only once a hangout exists and they have joined it. That is the
/// guardrail against the product reading like a dating app, and it is enforced
/// by the shape of the data rather than by what this widget chooses to render.
library;

class HangoutNudge {
  /// How many people within [radiusKm] share [interestKey]. Never includes
  /// the viewer.
  final int nearbyCount;

  /// The `event_categories.key` — e.g. `nightlife`. Carried so the create
  /// flow can pre-select a real category instead of defaulting to `'other'`.
  final String interestKey;

  /// Human label straight from `event_categories.label`, never hardcoded:
  /// that table is the contract with web (team_comms #173/#174).
  final String interestLabel;

  final String interestEmoji;
  final int radiusKm;

  const HangoutNudge({
    required this.nearbyCount,
    required this.interestKey,
    required this.interestLabel,
    required this.interestEmoji,
    required this.radiusKm,
  });

  /// Parses one row, or null if the row cannot make a sentence.
  ///
  /// Returns null rather than a zero-valued object on purpose: a nudge with no
  /// count or no label has nothing to say, and the caller's contract is
  /// "null means render nothing". A partially-populated object would have to
  /// be re-checked at every call site.
  static HangoutNudge? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final count = (json['nearby_count'] as num?)?.toInt() ?? 0;
    final label = (json['interest_label'] as String?)?.trim() ?? '';
    if (count <= 0 || label.isEmpty) return null;
    return HangoutNudge(
      nearbyCount: count,
      interestKey: (json['interest_key'] as String?)?.trim() ?? '',
      interestLabel: label,
      interestEmoji: (json['interest_emoji'] as String?)?.trim() ?? '',
      radiusKm: (json['radius_km'] as num?)?.toInt() ?? 0,
    );
  }

  /// The headline. Reads as a fact about the world, not a marketing line.
  String get headline => '$nearbyCount people near you are into $interestLabel';

  /// The ask. Says what the user would actually be doing, because "Get
  /// started" tells someone nothing about what happens when they tap it.
  String get ctaLabel => 'Start something';

  /// Why those people and not others. Without this the count reads as a
  /// claim; with it, it reads as a measurement the user can sanity-check.
  String get subtitle => radiusKm > 0
      ? 'Within $radiusKm km, active recently. Pick a spot and a time — '
          'we\'ll let them know.'
      : 'Pick a spot and a time — we\'ll let them know.';
}
