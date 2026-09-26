/// Who is actually coming to a hangout, and how to say it.
///
/// 63% of hangouts in the last 90 days got nobody, and the UI could not tell
/// you which ones: the host is itself a `table_members` row, so a hangout with
/// zero guests rendered one avatar and "1 / 4 spots" — identical to a hangout
/// someone had joined. This type exists so every surface counts the same way
/// and says the same thing.
enum HangoutViewerState { none, going, interested, pending, host }

class HangoutSocialProof {
  /// GUESTS only — never includes the host. 0 means nobody came.
  final int goingCount;

  /// People who tapped Interested. They hold no spot and are not guests yet.
  final int interestedCount;

  /// Everyone holding a spot, host included — this is the number the server
  /// compares against max_guests when someone tries to join, so it is the only
  /// correct basis for "how many spots are left".
  final int occupied;

  final int maxGuests;
  final bool isHost;

  /// Up to 3 guest faces, already block-filtered by the server.
  final List<String> avatars;

  final HangoutViewerState viewerState;

  const HangoutSocialProof({
    required this.goingCount,
    required this.interestedCount,
    required this.occupied,
    required this.maxGuests,
    required this.isHost,
    required this.avatars,
    required this.viewerState,
  });

  /// A hangout we know nothing about yet — renders as if empty, never crashes.
  static const unknown = HangoutSocialProof(
    goingCount: 0,
    interestedCount: 0,
    occupied: 0,
    maxGuests: 0,
    isHost: false,
    avatars: [],
    viewerState: HangoutViewerState.none,
  );

  factory HangoutSocialProof.fromJson(Map<String, dynamic> json) {
    return HangoutSocialProof(
      goingCount: (json['going_count'] as num?)?.toInt() ?? 0,
      interestedCount: (json['interested_count'] as num?)?.toInt() ?? 0,
      occupied: (json['occupied'] as num?)?.toInt() ?? 0,
      maxGuests: (json['max_guests'] as num?)?.toInt() ?? 0,
      isHost: json['is_host'] as bool? ?? false,
      avatars: (json['avatars'] as List?)
              ?.whereType<String>()
              .where((u) => u.isNotEmpty)
              .toList() ??
          const [],
      viewerState: _stateFrom(json['viewer_state'] as String?),
    );
  }

  static HangoutViewerState _stateFrom(String? raw) {
    switch (raw) {
      case 'host':
        return HangoutViewerState.host;
      case 'going':
        return HangoutViewerState.going;
      case 'interested':
        return HangoutViewerState.interested;
      case 'pending':
        return HangoutViewerState.pending;
      default:
        return HangoutViewerState.none;
    }
  }

  bool get isEmpty => goingCount == 0;

  /// Spots a new guest could take. Never negative — an over-filled hangout
  /// (host raised nobody but lowered max_guests) reads as full, not as -2.
  int get spotsLeft => maxGuests <= 0 ? 0 : (maxGuests - occupied).clamp(0, maxGuests);

  bool get isFull => maxGuests > 0 && spotsLeft == 0;

  /// Above this, "needs N more" stops being an ask and starts being noise —
  /// hangouts created through the legacy modal carry max_guests 30, and
  /// "needs 29 more" reads as nobody is coming, which is the opposite of the
  /// nudge. Large-capacity hangouts get no ask line at all.
  static const int maxMeaningfulAsk = 8;

  /// The headline: how many people are coming.
  ///
  /// The host sees a different empty state from a visitor — telling the host to
  /// "be the first to join" their own hangout is nonsense.
  String get goingLabel {
    if (goingCount > 0) return '$goingCount going';
    if (interestedCount > 0) {
      return '$interestedCount interested';
    }
    return isHost || viewerState == HangoutViewerState.host
        ? 'No one has joined yet'
        : 'Be the first to join';
  }

  /// Same meaning as [goingLabel], short enough for a feed card's trailing
  /// column, where the left side holds an Expanded and the label would
  /// otherwise ellipsize to "Be the first to...".
  String get goingLabelCompact {
    if (goingCount > 0) return '$goingCount going';
    if (interestedCount > 0) return '$interestedCount interested';
    return isHost || viewerState == HangoutViewerState.host
        ? 'No one yet'
        : 'Be first';
  }

  /// The ask — "Needs 3 more" — or null when there is nothing useful to say.
  String? get needsMoreLabel {
    if (isFull) return null;
    final left = spotsLeft;
    if (left <= 0 || left > maxMeaningfulAsk) return null;
    return 'Needs $left more';
  }

  /// Secondary line: interest that has not converted yet. Only worth showing
  /// alongside a real going count — on an empty hangout the interest count is
  /// already the headline.
  String? get interestedSuffix {
    if (interestedCount <= 0) return null;
    if (goingCount == 0) return null;
    return '$interestedCount interested';
  }

  bool get canJoin =>
      viewerState == HangoutViewerState.none ||
      viewerState == HangoutViewerState.interested;

  bool get canMarkInterested => viewerState == HangoutViewerState.none;

  HangoutSocialProof copyWith({
    int? goingCount,
    int? interestedCount,
    int? occupied,
    HangoutViewerState? viewerState,
  }) {
    return HangoutSocialProof(
      goingCount: goingCount ?? this.goingCount,
      interestedCount: interestedCount ?? this.interestedCount,
      occupied: occupied ?? this.occupied,
      maxGuests: maxGuests,
      isHost: isHost,
      avatars: avatars,
      viewerState: viewerState ?? this.viewerState,
    );
  }
}
