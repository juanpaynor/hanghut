/// What a host actually changed about a hangout.
///
/// This exists as its own value because of what a field being non-null means
/// downstream: `update_hangout` pushes "Plans changed" to everyone who
/// committed whenever the **time or the place** arrives. So echoing back an
/// unchanged venue alongside a corrected typo would notify the whole group for
/// nothing — and over-notifying a group of six is how a hangout loses the
/// people it had. Every null here is load-bearing, not tidiness.
///
/// The venue is one unit. Name, coordinates and address travel together or not
/// at all: a new name on the old coordinates leaves the pin somewhere nobody
/// agreed to, and new coordinates under the old address sends people to the
/// previous place. The RPC refuses a half-moved venue, and
/// [HangoutEditDiff.between] cannot construct one.
class HangoutEditDiff {
  /// Null when unchanged. An empty or whitespace-only title counts as
  /// unchanged rather than as a request to blank it — `tables.title` is
  /// NOT NULL, and a nameless hangout is not something to offer a host.
  final String? title;

  /// Null when unchanged. Unlike the title, an empty string here is a real
  /// change: clearing the notes is a thing a host may want.
  final String? description;

  final DateTime? datetime;

  /// These four are all-or-nothing — see the class comment.
  final String? locationName;
  final String? venueAddress;
  final double? latitude;
  final double? longitude;

  final int? maxGuests;

  const HangoutEditDiff({
    this.title,
    this.description,
    this.datetime,
    this.locationName,
    this.venueAddress,
    this.latitude,
    this.longitude,
    this.maxGuests,
  });

  /// Compares what the host now has against what the editor opened with.
  ///
  /// The comparison is against the **opening** values, not the live row, so a
  /// change made elsewhere mid-edit cannot be silently reverted by a field
  /// this host never touched.
  ///
  /// A venue is considered moved only when [newVenueLat] and [newVenueLng] are
  /// both present and are not the null island — the (0, 0) coordinate that put
  /// existing hangouts in the Gulf of Guinea, which this editor is the repair
  /// tool for and must never reintroduce.
  factory HangoutEditDiff.between({
    required String originalTitle,
    required String currentTitle,
    required String originalDescription,
    required String currentDescription,
    required DateTime originalDateTime,
    required DateTime currentDateTime,
    required int originalMaxGuests,
    required int currentMaxGuests,
    String? newVenueName,
    String? newVenueAddress,
    double? newVenueLat,
    double? newVenueLng,
  }) {
    final trimmedTitle = currentTitle.trim();
    final trimmedDescription = currentDescription.trim();

    final venueMoved =
        newVenueName != null &&
        newVenueName.trim().isNotEmpty &&
        newVenueLat != null &&
        newVenueLng != null &&
        !(newVenueLat == 0 && newVenueLng == 0);

    return HangoutEditDiff(
      title: (trimmedTitle.isNotEmpty && trimmedTitle != originalTitle)
          ? trimmedTitle
          : null,
      description: trimmedDescription != originalDescription
          ? trimmedDescription
          : null,
      datetime: currentDateTime != originalDateTime ? currentDateTime : null,
      locationName: venueMoved ? newVenueName.trim() : null,
      // An empty address is sent as empty, not dropped: the pin moved, so the
      // old street address is now wrong and has to go even when the new pick
      // brought none with it.
      venueAddress: venueMoved ? (newVenueAddress ?? '') : null,
      latitude: venueMoved ? newVenueLat : null,
      longitude: venueMoved ? newVenueLng : null,
      maxGuests: currentMaxGuests != originalMaxGuests ? currentMaxGuests : null,
    );
  }

  bool get isEmpty =>
      title == null &&
      description == null &&
      datetime == null &&
      locationName == null &&
      latitude == null &&
      maxGuests == null;

  bool get isNotEmpty => !isEmpty;

  bool get venueChanged => locationName != null;

  bool get timeChanged => datetime != null;

  /// True when saving this will push every committed member.
  ///
  /// Surfaced in the editor before the save, not after: a host who knows the
  /// group is about to be told makes all their corrections in one pass
  /// instead of three.
  bool get notifiesMembers => timeChanged || venueChanged;
}
