/// Whether a tier can be bought right now. Ported from web's
/// `src/lib/tickets/tier-availability.ts` (team_comms #320) so the two clients
/// cannot drift — port it, do not re-derive it.
///
/// The server enforces the same rules in create-purchase-intent with matching
/// codes: TIER_LOCKED / TIER_NOT_YET_ON_SALE / TIER_SALES_CLOSED. This
/// predicate exists so the buyer never SEES a tier they cannot buy; the 409
/// exists because device clocks drift and a screen can be left open across
/// the boundary.
enum TierSaleState {
  /// Buyable now.
  onSale,

  /// Has a `sales_start` in the future.
  scheduled,

  /// Has a `sales_end` in the past.
  closed,

  /// The organizer's manual switch.
  locked,
}

class TicketTier {
  final String id;
  final String eventId;
  final String name;
  final String? description;
  final double price;
  final int quantityTotal;
  final int quantitySold;

  /// Tri-state on the wire. NULL means "never configured" and is ON SALE —
  /// every tier that predates the column has NULL, so treating it as locked
  /// would close the whole back catalogue. Only an explicit `false` locks.
  final bool? isActiveRaw;

  /// timestamptz, UTC on the wire. Parsed to an instant; compared as instants.
  final DateTime? salesStart;
  final DateTime? salesEnd;

  /// The SAME flag that already governed the manual lock. It now covers all
  /// three un-buyable states — there is no new setting.
  final bool showWhenLocked;

  /// Organizer-written reason. Always wins over the generic state label.
  final String? lockNote;

  TicketTier({
    required this.id,
    required this.eventId,
    required this.name,
    this.description,
    required this.price,
    required this.quantityTotal,
    required this.quantitySold,
    this.isActiveRaw,
    this.salesStart,
    this.salesEnd,
    this.showWhenLocked = false,
    this.lockNote,
  });

  factory TicketTier.fromJson(Map<String, dynamic> json) {
    return TicketTier(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      quantityTotal: json['quantity_total'] as int,
      quantitySold: json['quantity_sold'] as int? ?? 0,
      isActiveRaw: json['is_active'] as bool?,
      // tryParse, never parse: an unparseable timestamp must be treated as
      // NULL (no boundary), never as closed. A typo in the database should
      // not stop a sale.
      salesStart: DateTime.tryParse(json['sales_start']?.toString() ?? ''),
      salesEnd: DateTime.tryParse(json['sales_end']?.toString() ?? ''),
      showWhenLocked: json['show_when_locked'] == true,
      lockNote: (json['lock_note'] as String?)?.trim().isEmpty == true
          ? null
          : json['lock_note'] as String?,
    );
  }

  /// Kept for existing callers: the manual switch only.
  bool get isActive => isActiveRaw != false;

  int get quantityAvailable => quantityTotal - quantitySold;
  bool get isSoldOut => quantityAvailable <= 0;

  /// The manual lock is checked FIRST. An organizer who flipped a tier off
  /// means it now, whatever its schedule says — reporting "opens Friday" for
  /// something a human deliberately closed would be a lie the schedule
  /// happens to make available.
  ///
  /// Pure function of [now]: never cache the RESULT. A list computed at 2:59
  /// and drawn at 3:01 shows a tier that just closed as buyable, which is
  /// precisely the bug this exists to prevent. Evaluate at render time.
  TierSaleState saleState([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (isActiveRaw == false) return TierSaleState.locked;
    if (salesStart != null && salesStart!.isAfter(t)) {
      return TierSaleState.scheduled;
    }
    if (salesEnd != null && salesEnd!.isBefore(t)) return TierSaleState.closed;
    return TierSaleState.onSale;
  }

  /// Can a buyer put this in their basket?
  bool isOnSale([DateTime? now]) => saleState(now) == TierSaleState.onSale;

  /// Should the tier appear on the page at all? Un-buyable tiers vanish
  /// unless the organizer ticked "show when locked".
  bool isVisible([DateTime? now]) => isOnSale(now) || showWhenLocked;

  /// The badge on an un-buyable tier, or null when it is on sale.
  ///
  /// "Opens `<date>`" carries the date; "Sales closed" deliberately does not.
  /// Naming the moment something opens is useful — a buyer can come back.
  /// Naming the moment it shut only tells them how narrowly they missed it.
  ///
  /// [formatOpens] renders the opening instant; the caller owns the format so
  /// this model stays free of intl. Web renders Asia/Manila; the app renders
  /// device-local like every other time on the purchase screen (declared to
  /// web in #322 — they differ only for a buyer outside UTC+8).
  String? saleLabel({
    DateTime? now,
    required String Function(DateTime opens) formatOpens,
  }) {
    final state = saleState(now);
    if (state == TierSaleState.onSale) return null;
    if (lockNote != null) return lockNote;
    if (state == TierSaleState.scheduled && salesStart != null) {
      return 'Opens ${formatOpens(salesStart!)}';
    }
    if (state == TierSaleState.closed) return 'Sales closed';
    return 'Not on sale';
  }
}
