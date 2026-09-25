/// The terms a buyer must accept before paying (team_comms #332).
///
/// Two gates, both mandatory, both blocking the pay button:
///  1. HangHut's own Terms of Service — always.
///  2. The organizer's terms — whenever the event has any.
///
/// Web has required both acceptances since checkout was built; the app
/// required neither, so the same ticket bought through the app agreed to
/// nothing. For 67 live events that text is a refund policy, a liability
/// waiver or race rules.
class CheckoutTerms {
  /// The organizer's terms as shown to the buyer, or null when there are none.
  final String? organizerTerms;

  const CheckoutTerms({this.organizerTerms});

  /// Resolves the organizer's terms from an `events` row selected with
  /// `custom_tos, partners:organizer_id (custom_tos)`.
  ///
  /// Event-level text wins; otherwise the partner's terms apply to every event
  /// they run. Whitespace-only text counts as absent — an organizer who
  /// cleared the field has no terms, and an empty box with a checkbox under it
  /// is worse than no box at all.
  factory CheckoutTerms.fromEventRow(Map<String, dynamic>? row) {
    if (row == null) return const CheckoutTerms();
    final own = (row['custom_tos'] ?? '').toString().trim();
    if (own.isNotEmpty) return CheckoutTerms(organizerTerms: own);
    final partner = (row['partners']?['custom_tos'] ?? '').toString().trim();
    return CheckoutTerms(organizerTerms: partner.isEmpty ? null : partner);
  }

  bool get hasOrganizerTerms => (organizerTerms ?? '').trim().isNotEmpty;

  /// Whether payment may proceed. The organizer gate only applies when there
  /// is something to accept, so an event without terms needs one tick, not two.
  bool accepted({required bool platform, required bool organizer}) =>
      platform && (!hasOrganizerTerms || organizer);
}
