import 'package:bitemates/features/ticketing/models/ticket_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Port of web's tier-availability rules (team_comms #320). Each case here is
/// one the message called out as easy to get wrong.
void main() {
  final now = DateTime.utc(2026, 9, 20, 12); // fixed instant, never the clock
  final past = now.subtract(const Duration(hours: 1)).toIso8601String();
  final future = now.add(const Duration(hours: 1)).toIso8601String();

  TicketTier tier(Map<String, dynamic> extra) => TicketTier.fromJson({
        'id': 't1',
        'event_id': 'e1',
        'name': 'GA',
        'price': 500,
        'quantity_total': 10,
        'quantity_sold': 0,
        ...extra,
      });

  String fmt(DateTime d) => d.toIso8601String();

  group('precedence', () {
    test('manual lock beats a schedule that says "opens later"', () {
      final t = tier({'is_active': false, 'sales_start': future});
      expect(t.saleState(now), TierSaleState.locked);
      expect(t.saleLabel(now: now, formatOpens: fmt), 'Not on sale');
    });

    test('sales_start in the future → scheduled, with the date', () {
      final t = tier({'sales_start': future});
      expect(t.saleState(now), TierSaleState.scheduled);
      expect(t.saleLabel(now: now, formatOpens: fmt), startsWith('Opens '));
    });

    test('sales_end in the past → closed, deliberately without a date', () {
      final t = tier({'sales_end': past});
      expect(t.saleState(now), TierSaleState.closed);
      expect(t.saleLabel(now: now, formatOpens: fmt), 'Sales closed');
    });

    test('inside the window → on sale, no label', () {
      final t = tier({'sales_start': past, 'sales_end': future});
      expect(t.saleState(now), TierSaleState.onSale);
      expect(t.saleLabel(now: now, formatOpens: fmt), isNull);
    });
  });

  group('the three traps', () {
    test('is_active NULL means never configured → ON SALE, not locked', () {
      final t = tier({'is_active': null});
      expect(t.saleState(now), TierSaleState.onSale);
      expect(t.isActive, isTrue);
    });

    test('absent is_active (old rows) → on sale', () {
      expect(tier({}).saleState(now), TierSaleState.onSale);
    });

    test('unparseable timestamp is NO boundary, never closed', () {
      final t = tier({'sales_start': 'next friday', 'sales_end': 'garbage'});
      expect(t.salesStart, isNull);
      expect(t.salesEnd, isNull);
      expect(t.saleState(now), TierSaleState.onSale);
    });
  });

  group('visibility and labels', () {
    test('un-buyable tiers are hidden unless show_when_locked', () {
      expect(tier({'sales_end': past}).isVisible(now), isFalse);
      expect(
        tier({'sales_end': past, 'show_when_locked': true}).isVisible(now),
        isTrue,
      );
    });

    test('on-sale tiers are always visible regardless of the flag', () {
      expect(tier({'show_when_locked': false}).isVisible(now), isTrue);
    });

    test('lock_note always wins over the generic label', () {
      final t = tier({
        'sales_start': future,
        'lock_note': 'Members only until launch',
      });
      expect(
        t.saleLabel(now: now, formatOpens: fmt),
        'Members only until launch',
      );
    });

    test('blank lock_note is treated as absent', () {
      final t = tier({'sales_end': past, 'lock_note': '   '});
      expect(t.saleLabel(now: now, formatOpens: fmt), 'Sales closed');
    });
  });

  test('state is a function of now — same row, two instants, two answers', () {
    final t = tier({'sales_end': future});
    expect(t.saleState(now), TierSaleState.onSale);
    expect(
      t.saleState(now.add(const Duration(hours: 2))),
      TierSaleState.closed,
    );
  });
}
