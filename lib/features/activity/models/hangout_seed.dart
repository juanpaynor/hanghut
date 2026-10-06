/// A system-made suggestion: an activity, a place and a time, already chosen.
///
/// "☕ Grab coffee at Yardstick Coffee, Saturday 10AM" — the user's only job is
/// to say yes. That is the whole point: the blank create form asks for a
/// venue, a time and a description before anything exists, and that is where
/// people drop out.
///
/// All three parts come from what people here already do. The activity list is
/// derived from real hangout titles (coffee is the most-created and the best
/// converting); the venue from where hangouts have actually happened, so a
/// coffee suggestion names somewhere people have genuinely had coffee.
///
/// Deliberately NOT built on ticketed events. An earlier version suggested
/// going to gigs and workshops together, which fails on its own terms: an
/// event means two people each buying a ticket, which is commerce rather than
/// a hangout. In 177 hangouts nobody has ever created one to attend a ticketed
/// event.
///
/// A suggestion is NOT a hangout. Nothing is on the map, no chat exists and
/// nobody is committed until someone says yes — at which point the hangout is
/// created server-side with them as host and everyone else who said yes is
/// invited to it.
///
/// It carries **no identities**, by RLS and by shape: a candidate can read
/// their own row and the suggestion, never the other candidates. [goingCount]
/// is an aggregate for exactly that reason.
library;

/// Where a suggestion has got to.
enum HangoutSeedStatus {
  /// Nobody has taken it on. The first person to say yes hosts it.
  open,

  /// Someone is hosting. A real hangout exists to join.
  claimed,

  /// Expired, cancelled, or unrecognised — render nothing.
  gone,
}

class HangoutSeed {
  final String seedId;

  /// A `hangout_activities.slug` — coffee, drinks, run… Carried through to the
  /// created hangout so it has a real category instead of `'other'`, which is
  /// why every vibe chip used to match nothing.
  final String activitySlug;

  /// "Grab coffee"
  final String activityTitle;
  final String emoji;

  /// Klipy search term for the modal's GIF. Comes from the catalogue because
  /// the activity makes a good query and the venue name does not — "coffee
  /// with friends" returns the right mood, "Yardstick Coffee" returns nothing.
  final String gifQuery;

  final String venueName;
  final double latitude;
  final double longitude;

  /// The suggested time. The host can change it once they accept.
  final DateTime proposedAt;

  /// How many people nearby could come. Not a promise that they will.
  final int poolSize;

  /// How many have already said yes. Social proof, aggregate only.
  final int goingCount;

  final HangoutSeedStatus status;

  /// The real hangout, once someone has said yes. Null while open.
  final String? claimedTableId;

  /// 'in', 'out', or null when the user has not answered.
  final String? myResponse;

  const HangoutSeed({
    required this.seedId,
    required this.activitySlug,
    required this.activityTitle,
    required this.emoji,
    required this.gifQuery,
    required this.venueName,
    required this.latitude,
    required this.longitude,
    required this.proposedAt,
    required this.poolSize,
    required this.goingCount,
    required this.status,
    this.claimedTableId,
    this.myResponse,
  });

  /// Parses one row, or null when there is nothing worth showing.
  ///
  /// Null rather than a partially-filled object: every field is load bearing
  /// for the sentence the card makes, and a suggestion missing its place or
  /// its time is the vague prompt this exists to replace.
  static HangoutSeed? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final id = (json['seed_id'] as String?)?.trim() ?? '';
    final title = (json['activity_title'] as String?)?.trim() ?? '';
    final venue = (json['venue_name'] as String?)?.trim() ?? '';
    final rawWhen = json['proposed_at'];
    final when = rawWhen == null ? null : DateTime.tryParse('$rawWhen');

    if (id.isEmpty || title.isEmpty || venue.isEmpty || when == null) {
      return null;
    }

    // (0, 0) is null island, not a venue — the same guard the create flows
    // apply. A suggestion plotted there could never be found by anyone.
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;

    final status = switch ((json['status'] as String?)?.trim()) {
      'open' => HangoutSeedStatus.open,
      'claimed' => HangoutSeedStatus.claimed,
      _ => HangoutSeedStatus.gone,
    };
    if (status == HangoutSeedStatus.gone) return null;

    // Suggesting a plan for a time that has passed is the clearest possible
    // way to look broken.
    if (when.isBefore(DateTime.now())) return null;

    return HangoutSeed(
      seedId: id,
      activitySlug: (json['activity_slug'] as String?)?.trim() ?? '',
      activityTitle: title,
      emoji: (json['emoji'] as String?)?.trim() ?? '',
      gifQuery: (json['gif_query'] as String?)?.trim() ?? '',
      venueName: venue,
      latitude: lat,
      longitude: lng,
      proposedAt: when.toLocal(),
      poolSize: (json['pool_size'] as num?)?.toInt() ?? 0,
      goingCount: (json['going_count'] as num?)?.toInt() ?? 0,
      status: status,
      claimedTableId: (json['claimed_table_id'] as String?)?.trim(),
      myResponse: (json['my_response'] as String?)?.trim(),
    );
  }

  bool get isOpen => status == HangoutSeedStatus.open;

  bool get alreadySaidYes => myResponse == 'in';

  /// Whether to ask at all. Someone who already said yes has answered;
  /// re-asking reads as the app having lost their reply.
  bool get needsAnswer => isOpen && myResponse == null;

  /// "Grab coffee at Yardstick Coffee"
  String get headline => '$activityTitle at $venueName';

  /// "Sat 10 Oct, 10:00am" — weekday first, because a bare date makes the
  /// reader work out whether it is soon.
  String get whenLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = days[(proposedAt.weekday - 1) % 7];
    final month = months[(proposedAt.month - 1) % 12];
    final hour24 = proposedAt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 < 12 ? 'am' : 'pm';
    final minutes = proposedAt.minute == 0
        ? ''
        : ':${proposedAt.minute.toString().padLeft(2, '0')}';
    return '$day ${proposedAt.day} $month, $hour12$minutes$suffix';
  }

  /// The ask line. Leads with people who already said yes when there are any,
  /// because committed company persuades where a headcount does not.
  String get poolLabel {
    if (goingCount > 0) {
      return goingCount == 1
          ? '1 person is already in'
          : '$goingCount people are already in';
    }
    return poolSize > 0
        ? '$poolSize people near you are up for this'
        : 'Nobody has made a plan yet';
  }

  /// What saying yes commits them to, stated plainly.
  String get subtitle => status == HangoutSeedStatus.claimed
      ? 'Someone is hosting this — say yes and you are in.'
      : 'Say yes and it is yours to host. You can change the spot or time.';
}
