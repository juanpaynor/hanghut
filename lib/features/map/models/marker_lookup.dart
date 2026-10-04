/// Reading a tapped Mapbox feature's `properties` back into our own lists.
///
/// These are pure functions in their own file so the rule can be tested. The
/// bug they exist to prevent was live: a marker carrying `index: -1` passed
/// every `index < list.length` check in the tap handlers and threw
/// `RangeError (length): Invalid value: Not in inclusive range 0..5: -1`.
library;

/// The `index` a marker feature carries, or null if it has none or it is not
/// a number.
///
/// Parsed via `toString()` rather than cast: the value arrives through the
/// platform channel and has been seen as an `int`, a `double` and a `String`
/// depending on layer and platform. One handler used `index is int` and so
/// silently dropped taps on the other two.
int? markerIndex(Map? properties) {
  final raw = properties?['index'];
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

/// The stable id an event marker carries, or null if it has none.
///
/// Preferred over [markerIndex] for events. The index is a position in a list
/// that is replaced wholesale on every viewport refetch; the id is not.
String? markerEventId(Map? properties) {
  final raw = properties?['event_id']?.toString();
  return (raw == null || raw.isEmpty) ? null : raw;
}

/// Resolves a marker index to a list element, or null if it cannot.
///
/// Both bounds, deliberately. A marker that outlives the fetch which drew it
/// carries an index into a list that no longer exists, and `indexOf` failures
/// make that index **negative** rather than merely too large.
T? markerItem<T>(List<T> list, int? index) =>
    (index != null && index >= 0 && index < list.length) ? list[index] : null;
