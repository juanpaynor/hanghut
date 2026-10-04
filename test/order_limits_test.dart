import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/ticketing/models/order_limits.dart';
import 'package:bitemates/features/ticketing/models/ticket_tier.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

/// Per-order quantity limits (team_comms #345).
///
/// The headline case is the one web shipped wrong: a tier must never be able
/// to RAISE an event's cap. Their picker used `tier?.max_per_order ||
/// eventMax`, and because an untouched tier defaults to 10, an organizer who
/// set "1 per purchase" on the event was silently overridden.
void main() {
  group('effectivePerOrderCap', () {
    test('a tier cannot raise the event cap — the exact bug web shipped', () {
      // Organizer set 1 on the event and never touched the tier, which sits on
      // its default of 10. `tier ?? event` yields 10. The answer is 1.
      expect(effectivePerOrderCap(eventCap: 1, tierCap: 10), 1);
    });

    test('a tier can tighten the event cap', () {
      expect(effectivePerOrderCap(eventCap: 10, tierCap: 2), 2);
    });

    test('an unset tier cap defers to the event', () {
      expect(effectivePerOrderCap(eventCap: 4, tierCap: null), 4);
    });

    test('equal bounds are stable', () {
      expect(effectivePerOrderCap(eventCap: 6, tierCap: 6), 6);
    });

    test('never returns below 1, so a bad row cannot take a sale offline', () {
      expect(effectivePerOrderCap(eventCap: 0, tierCap: null), 1);
      expect(effectivePerOrderCap(eventCap: 0, tierCap: 0), 1);
      expect(effectivePerOrderCap(eventCap: -5, tierCap: -5), 1);
    });

    test('the real SINADYA RUN case: qty 6 was offered against a cap of 1', () {
      // events.max_tickets_per_purchase defaulted to 10, ticket_tiers
      // .max_per_order was 1 on the 21KM tier. The old code read neither and
      // allowed 6 — ₱14,994 of entries the server would now refuse.
      expect(effectivePerOrderCap(eventCap: 10, tierCap: 1), 1);
    });
  });

  group('effectivePerOrderFloor', () {
    test('the higher floor wins — a tier may tighten, never loosen', () {
      expect(effectivePerOrderFloor(eventFloor: 1, tierFloor: 2, cap: 10), 2);
      expect(effectivePerOrderFloor(eventFloor: 3, tierFloor: 2, cap: 10), 3);
    });

    test('an unset tier floor defers to the event', () {
      expect(effectivePerOrderFloor(eventFloor: 2, tierFloor: null, cap: 10), 2);
    });

    test('a floor above the cap is clamped, never left unsatisfiable', () {
      // Otherwise the stepper has no legal value and both buttons disable.
      expect(effectivePerOrderFloor(eventFloor: 8, tierFloor: null, cap: 3), 3);
    });

    test('never returns below 1', () {
      expect(effectivePerOrderFloor(eventFloor: 0, tierFloor: 0, cap: 5), 1);
    });
  });

  group('effectiveMaxQuantity', () {
    test('stock binds when it is lower than the cap', () {
      expect(effectiveMaxQuantity(stockAvailable: 2, cap: 10), 2);
    });

    test('the cap binds when stock is plentiful', () {
      expect(effectiveMaxQuantity(stockAvailable: 300, cap: 2), 2);
    });

    test('sold out still reports 1, because clamp() upper bounds must be >= 1',
        () {
      expect(effectiveMaxQuantity(stockAvailable: 0, cap: 10), 1);
      expect(effectiveMaxQuantity(stockAvailable: -3, cap: 10), 1);
    });
  });

  group('TicketTier per-order parsing', () {
    TicketTier tier(Map<String, dynamic> extra) => TicketTier.fromJson({
          'id': 't1',
          'event_id': 'e1',
          'name': '21KM',
          'price': 2499,
          'quantity_total': 300,
          'quantity_sold': 10,
          ...extra,
        });

    test('absent stays null so the event cap wins — not defaulted to 10', () {
      // Defaulting here would silently re-introduce the "tier raises the event
      // cap" bug through the model instead of the picker.
      expect(tier({}).maxPerOrder, isNull);
      expect(tier({}).minPerOrder, isNull);
    });

    test('reads max_per_order and min_per_order', () {
      final t = tier({'max_per_order': 1, 'min_per_order': 2});
      expect(t.maxPerOrder, 1);
      expect(t.minPerOrder, 2);
    });

    test('a nonsense 0 floors to 1 rather than making the tier unbuyable', () {
      expect(tier({'max_per_order': 0}).maxPerOrder, 1);
    });

    test('accepts a numeric type from the wire', () {
      expect(tier({'max_per_order': 3.0}).maxPerOrder, 3);
    });
  });

  group('Event.maxPerOrder takes the lower of the two columns', () {
    Event event(Map<String, dynamic> extra) => Event.fromJson({
          'id': 'e1',
          'title': 'KOOLCHELLA',
          'description': '',
          'venue_name': 'Somewhere',
          'start_datetime': '2026-10-25T12:00:00Z',
          'ticket_price': 1000,
          'capacity': 500,
          'created_at': '2026-09-01T00:00:00Z',
          ...extra,
        });

    test('max_tickets_per_purchase wins when it is the stricter one', () {
      // The live column, which our host screen writes and web enforces, while
      // checkout used to read only max_seats_per_order.
      final e = event({
        'max_seats_per_order': 10,
        'max_tickets_per_purchase': 1,
      });
      expect(e.maxPerOrder, 1);
    });

    test('max_seats_per_order still wins if it is ever the stricter one', () {
      final e = event({
        'max_seats_per_order': 2,
        'max_tickets_per_purchase': 10,
      });
      expect(e.maxPerOrder, 2);
    });

    test('both absent defaults to 10, the pre-existing behaviour', () {
      expect(event({}).maxPerOrder, 10);
    });

    test('min_tickets_per_purchase is exposed as the floor', () {
      expect(event({'min_tickets_per_purchase': 2}).minPerOrder, 2);
      expect(event({}).minPerOrder, 1);
    });
  });
}
