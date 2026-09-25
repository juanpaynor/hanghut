import 'package:bitemates/features/ticketing/models/checkout_terms.dart';
import 'package:flutter_test/flutter_test.dart';

/// team_comms #332: web gates checkout on the HangHut ToS plus the organizer's
/// own terms; the app gated on neither. 67 live events carry organizer terms.
void main() {
  group('resolution', () {
    test("the event's own terms win over the partner's", () {
      final t = CheckoutTerms.fromEventRow({
        'custom_tos': 'Event waiver',
        'partners': {'custom_tos': 'Partner waiver'},
      });
      expect(t.organizerTerms, 'Event waiver');
    });

    test("the partner's terms apply when the event has none", () {
      final t = CheckoutTerms.fromEventRow({
        'custom_tos': null,
        'partners': {'custom_tos': 'Partner waiver'},
      });
      expect(t.organizerTerms, 'Partner waiver');
    });

    test('whitespace-only text counts as no terms, not an empty box', () {
      final t = CheckoutTerms.fromEventRow({
        'custom_tos': '   \n ',
        'partners': {'custom_tos': '  '},
      });
      expect(t.hasOrganizerTerms, isFalse);
    });

    test('no partner join and no event terms → none', () {
      expect(CheckoutTerms.fromEventRow({'custom_tos': null}).hasOrganizerTerms,
          isFalse);
      expect(CheckoutTerms.fromEventRow(null).hasOrganizerTerms, isFalse);
    });
  });

  group('the gate', () {
    const withTerms = CheckoutTerms(organizerTerms: 'Waiver');
    const without = CheckoutTerms();

    test('an event with organizer terms needs BOTH ticks', () {
      expect(withTerms.accepted(platform: true, organizer: false), isFalse);
      expect(withTerms.accepted(platform: false, organizer: true), isFalse);
      expect(withTerms.accepted(platform: true, organizer: true), isTrue);
    });

    test('an event without them needs only the platform tick', () {
      expect(without.accepted(platform: false, organizer: false), isFalse);
      expect(without.accepted(platform: true, organizer: false), isTrue);
    });

    test('the platform tick is never optional', () {
      expect(without.accepted(platform: false, organizer: true), isFalse);
    });
  });
}
