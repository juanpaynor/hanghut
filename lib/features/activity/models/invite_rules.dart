/// When is a hangout invitation actually open?
///
/// Pure functions in their own file so the rules can be tested. They exist
/// because this was wrong in three places at once: `acceptInvite` and
/// `declineInvite` matched `status = 'pending'` only, so against an `invited`
/// row they updated nothing — and a 0-row PostgREST update does not error, so
/// both reported success having saved nothing. Meanwhile the hangout modal
/// decided "am I invited" from a *different* record (`tables.invited_user_ids`)
/// than the one the accept wrote to.
library;

/// The membership statuses an open invitation can have.
///
/// Both, deliberately. `invited` is what every route writes now. `pending` is
/// ambiguous — it means EITHER "I asked to join and the host has not answered"
/// OR "the host invited me when they created this" — so a `pending` row only
/// counts as an invitation with the corroborating evidence in
/// [isOpenInvite]. Anything else (`joined`, `approved`, `attended`,
/// `declined`, `left`) is already answered.
const List<String> openInviteStatuses = ['invited', 'pending'];

/// Whether this membership row is an invitation awaiting the user's answer.
///
/// [namedInInvitedArray] is membership of the legacy `tables.invited_user_ids`
/// column, which is the only way to tell a create-time invite apart from the
/// user's own join request — both land as `pending`. Treating every `pending`
/// row as an invite would offer someone an "Accept" button for a request they
/// themselves sent.
bool isOpenInvite({
  required String? status,
  required bool namedInInvitedArray,
}) {
  if (status == 'invited') return true;
  if (status == 'pending') return namedInInvitedArray;
  return false;
}

/// Whether an invitation is still worth showing.
///
/// An invite to something that already happened, or to a hangout the host
/// cancelled, is not a decision — it is clutter. `expire_past_hangouts()`
/// moves a hangout off `open` six hours after its start time, so the status
/// check and the time check catch different things and both are needed.
bool isLiveInvite({
  required String? hangoutStatus,
  required DateTime? startsAt,
  required DateTime now,
}) {
  if (hangoutStatus != 'open') return false;
  if (startsAt == null) return false;
  return startsAt.isAfter(now);
}
