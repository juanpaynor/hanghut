/// How an event's and a tier's per-order bounds combine.
///
/// Extracted into pure functions on purpose: this is the rule web got wrong.
/// Their picker used `selectedTier?.max_per_order || eventMax`, so a tier
/// REPLACED the event's limit — and because an untouched tier defaults to 10,
/// an organizer who set "1 per purchase" on the event was silently overridden.
/// That was live on two of their events when they reported it (team_comms
/// #345). A rule this easy to get backwards belongs somewhere a test can reach
/// it, not inlined in a widget.
///
/// Both bounds are per ORDER, not per person. A buyer capped at 1 can check
/// out twice; neither platform implements per-person limits, so never describe
/// these as "one each".
library;

/// The most tickets one order may contain.
///
/// The LOWER of the two ceilings always wins. A tier may tighten an event's
/// limit; it may never loosen it. [tierCap] of null means the tier never
/// configured one, which defers to the event rather than imposing anything.
///
/// Always returns at least 1: a cap of 0 would make the tier unbuyable, and a
/// misconfigured row must not take a sale offline.
int effectivePerOrderCap({required int eventCap, int? tierCap}) {
  final cap = (tierCap == null || tierCap > eventCap) ? eventCap : tierCap;
  return cap < 1 ? 1 : cap;
}

/// The fewest tickets one order may contain, for tiers sold in multiples.
///
/// The HIGHER of the two floors wins, by the mirror of the argument above: a
/// tier may tighten, never loosen. Clamped to [cap], because a floor above the
/// ceiling would leave the stepper with no legal value at all.
int effectivePerOrderFloor({
  required int eventFloor,
  int? tierFloor,
  required int cap,
}) {
  final floor =
      (tierFloor == null || tierFloor < eventFloor) ? eventFloor : tierFloor;
  final bounded = floor < 1 ? 1 : floor;
  return bounded > cap ? cap : bounded;
}

/// What the quantity stepper may actually reach: whichever of real stock and
/// the per-order cap binds first. Never below 1, for the same reason as above.
int effectiveMaxQuantity({required int stockAvailable, required int cap}) {
  final limit = stockAvailable < cap ? stockAvailable : cap;
  return limit < 1 ? 1 : limit;
}
