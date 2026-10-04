/// Who is going to an event, and how to say it.
///
/// The mirror of [HangoutSocialProof] (lib/features/map/models), deliberately
/// shaped the same way so the two surfaces count and phrase things
/// identically. Events needed their own type rather than reusing that one:
/// there is no host, no capacity and no "spots left" here, and pretending
/// otherwise would mean carrying four fields that are always zero.
///
/// Why this exists at all: the app recorded 17,121 event interactions — 3,436
/// "get tickets" taps by 137 distinct users in 30 days — and showed none of it
/// to anyone. Every viewer saw an event that looked like nobody was going.
enum EventViewerState {
  /// No ticket, no interest registered.
  none,

  /// Tapped Interested. Holds nothing and has paid nothing.
  interested,

  /// Holds a real ticket. Outranks interest and cannot be toggled off — it is
  /// derived from the sale, not from a preference.
  going,
}

class EventSocialProof {
  /// Distinct PEOPLE holding a valid or used ticket.
  ///
  /// People, not ticket rows: buyers come in pairs, so the biggest event in the
  /// catalogue is 369 people across 733 rows. Guest buyers are included —
  /// 740 of ~804 upcoming ticket holders have no account, so an account-only
  /// count would render that event as empty.
  final int goingCount;

  /// People who tapped Interested.
  final int interestedCount;

  /// Up to 3 faces, already block-filtered by the server.
  ///
  /// Account holders only, so this is routinely far smaller than [goingCount] —
  /// 8 faces against 369 going on KOOLCHELLA. The number is the headline and
  /// these are a bonus; never gate the count on having faces.
  final List<String> avatars;

  final EventViewerState viewerState;

  const EventSocialProof({
    required this.goingCount,
    required this.interestedCount,
    required this.avatars,
    required this.viewerState,
  });

  /// An event we know nothing about yet.
  ///
  /// This is also what every event looks like before the server function
  /// exists, so it has to render as a plain, honest empty state rather than a
  /// spinner or a gap.
  static const unknown = EventSocialProof(
    goingCount: 0,
    interestedCount: 0,
    avatars: [],
    viewerState: EventViewerState.none,
  );

  factory EventSocialProof.fromJson(Map<String, dynamic> json) {
    return EventSocialProof(
      goingCount: (json['going_count'] as num?)?.toInt() ?? 0,
      interestedCount: (json['interested_count'] as num?)?.toInt() ?? 0,
      avatars: (json['avatars'] as List?)
              ?.whereType<String>()
              .where((u) => u.isNotEmpty)
              .toList() ??
          const [],
      viewerState: _stateFrom(json['viewer_state'] as String?),
    );
  }

  static EventViewerState _stateFrom(String? raw) {
    switch (raw) {
      case 'going':
        return EventViewerState.going;
      case 'interested':
        return EventViewerState.interested;
      default:
        return EventViewerState.none;
    }
  }

  bool get isEmpty => goingCount == 0 && interestedCount == 0;

  /// The headline.
  ///
  /// Only 9 of 84 upcoming events have a single buyer, so the third branch is
  /// the common one and has to be an invitation rather than a verdict.
  String get goingLabel {
    if (goingCount > 0) return '$goingCount going';
    if (interestedCount > 0) return '$interestedCount interested';
    return 'Be the first to go';
  }

  /// Same meaning, short enough for a card's trailing column where the full
  /// label would ellipsize to "Be the first to...".
  String get goingLabelCompact {
    if (goingCount > 0) return '$goingCount going';
    if (interestedCount > 0) return '$interestedCount interested';
    return 'Be first';
  }

  /// Interest that has not converted to a ticket, shown only alongside a real
  /// going count. On its own it is already the headline, and repeating it
  /// would read as two separate groups of people.
  String? get interestedSuffix {
    if (goingCount == 0 || interestedCount == 0) return null;
    return '$interestedCount interested';
  }

  /// Nothing to offer someone who already holds a ticket.
  bool get canMarkInterested => viewerState == EventViewerState.none;

  EventSocialProof copyWith({
    int? goingCount,
    int? interestedCount,
    List<String>? avatars,
    EventViewerState? viewerState,
  }) {
    return EventSocialProof(
      goingCount: goingCount ?? this.goingCount,
      interestedCount: interestedCount ?? this.interestedCount,
      avatars: avatars ?? this.avatars,
      viewerState: viewerState ?? this.viewerState,
    );
  }

  // Value equality so a widget can tell a refetch from its own optimistic
  // update and avoid clobbering one with the other.
  @override
  bool operator ==(Object other) =>
      other is EventSocialProof &&
      other.goingCount == goingCount &&
      other.interestedCount == interestedCount &&
      other.viewerState == viewerState &&
      _sameAvatars(other.avatars, avatars);

  static bool _sameAvatars(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(goingCount, interestedCount, viewerState, avatars.length);
}
