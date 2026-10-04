/// A system-made offer to go to something together.
///
/// The offer is anchored on a REAL upcoming event, which is the correction
/// that makes the whole feature coherent. An earlier version anchored on
/// venues harvested from the events table and then invented a date, which
/// produced proposals like "Gig night at Aseana City Concert Grounds" on a
/// day when that concert ground was an empty field — and one proposing
/// Monarch Manila six days *before* the real gig there.
///
/// An event supplies all three facts and invents none of them: what it is,
/// where it is, when it is. So the ask stops being "invent a reason to stand
/// somewhere" and becomes "this is on, people near you are into it, go
/// together?".
///
/// An offer is NOT a hangout. Nothing is on the map, no chat exists and
/// nobody is committed until someone says yes and becomes the host — at which
/// point a real `tables` row is created and everyone else who said yes is
/// invited to it.
///
/// It carries **no identities**, by RLS and by shape: a candidate can read
/// their own row and the offer, never the other candidates. [goingCount] is
/// an aggregate for exactly that reason.
library;

/// Where an offer has got to.
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

  /// An `event_categories.key`, passed to the create flow so the hangout
  /// carries a real category instead of `'other'`.
  final String category;

  final String interestLabel;
  final String interestEmoji;

  /// The real event this offer is about.
  final String? eventId;
  final String eventTitle;

  /// The event's own poster. More persuasive than anything we could generate,
  /// because it is the actual thing — may be absent, so never assume it.
  final String? coverImageUrl;

  final String venueName;
  final double latitude;
  final double longitude;

  /// The event's real start time. Not a suggestion we made up — though the
  /// host can still set their own meet-up time when they create the hangout.
  final DateTime proposedAt;

  /// How many people nearby share this interest.
  final int poolSize;

  /// How many have already said yes. Social proof, and an aggregate only.
  final int goingCount;

  final HangoutSeedStatus status;

  /// The real hangout, once someone has claimed this. Null while open.
  final String? claimedTableId;

  /// 'in', 'out', or null when the user has not answered.
  final String? myResponse;

  const HangoutSeed({
    required this.seedId,
    required this.category,
    required this.interestLabel,
    required this.interestEmoji,
    required this.eventTitle,
    required this.venueName,
    required this.latitude,
    required this.longitude,
    required this.proposedAt,
    required this.poolSize,
    required this.goingCount,
    required this.status,
    this.eventId,
    this.coverImageUrl,
    this.claimedTableId,
    this.myResponse,
  });

  /// Parses one row, or null when there is nothing to show.
  ///
  /// Null rather than a partially-filled object: every field here is load
  /// bearing for the question the card asks, and an offer missing its event
  /// or its time is not an offer — it is the blank form this exists to avoid.
  static HangoutSeed? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final id = (json['seed_id'] as String?)?.trim() ?? '';
    final title = (json['event_title'] as String?)?.trim() ?? '';
    final label = (json['interest_label'] as String?)?.trim() ?? '';
    final rawWhen = json['proposed_at'];
    final when = rawWhen == null ? null : DateTime.tryParse('$rawWhen');

    if (id.isEmpty || title.isEmpty || label.isEmpty || when == null) {
      return null;
    }

    // (0, 0) is null island, not a venue — the same guard the create flows
    // apply. An offer plotted there could never be found.
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;

    final status = switch ((json['status'] as String?)?.trim()) {
      'open' => HangoutSeedStatus.open,
      'claimed' => HangoutSeedStatus.claimed,
      _ => HangoutSeedStatus.gone,
    };
    if (status == HangoutSeedStatus.gone) return null;

    // Offering to go to something that has already happened is the clearest
    // possible way to look broken.
    if (when.isBefore(DateTime.now())) return null;

    final cover = (json['cover_image_url'] as String?)?.trim();

    return HangoutSeed(
      seedId: id,
      category: (json['category'] as String?)?.trim() ?? '',
      interestLabel: label,
      interestEmoji: (json['interest_emoji'] as String?)?.trim() ?? '',
      eventId: (json['event_id'] as String?)?.trim(),
      eventTitle: title,
      coverImageUrl: (cover == null || cover.isEmpty) ? null : cover,
      venueName: (json['venue_name'] as String?)?.trim() ?? '',
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

  /// Whether to ask the question at all. Someone who already said yes has
  /// answered; re-asking reads as the app having lost their reply.
  bool get needsAnswer => isOpen && myResponse == null;

  /// The event's own name. Real data beats anything we could template — the
  /// catalogue of invented titles this replaced could not produce
  /// "RUN FOR YOUR LIFE: A Zombie Marathon".
  String get headline => eventTitle;

  /// "Thu 15 Oct · Monarch Manila"
  String get whereAndWhen {
    final parts = [whenLabel, if (venueName.isNotEmpty) venueName];
    return parts.join(' · ');
  }

  /// "Thu 15 Oct" — weekday plus date, because a bare date makes the reader
  /// work out whether it is soon.
  String get whenLabel {
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = days[(proposedAt.weekday - 1) % 7];
    final month = months[(proposedAt.month - 1) % 12];
    return '$day ${proposedAt.day} $month';
  }

  /// The ask line. Leads with people who already said yes when there are any,
  /// because committed company persuades where a demographic count does not.
  String get poolLabel {
    if (goingCount > 0) {
      return goingCount == 1
          ? '1 person is already in'
          : '$goingCount people are already in';
    }
    return poolSize > 0
        ? '$poolSize people near you are into this'
        : 'Nobody has made a plan yet';
  }

  /// What saying yes actually commits them to, stated plainly.
  String get subtitle => status == HangoutSeedStatus.claimed
      ? 'Someone is hosting this — say yes and you are in.'
      : 'First to say yes hosts it. You pick where to meet.';
}
