import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';

/// The contract every call site relies on is "null means render nothing".
/// These tests pin that, because the alternative — a zero-valued object the
/// widget has to re-check — is how an empty nudge would end up on screen as
/// "0 people near you are into ".
void main() {
  Map<String, dynamic> row({
    Object? count = 22,
    Object? key = 'nightlife',
    Object? label = 'Nightlife',
    Object? emoji = '🌙',
    Object? radius = 15,
  }) => {
        'nearby_count': count,
        'interest_key': key,
        'interest_label': label,
        'interest_emoji': emoji,
        'radius_km': radius,
      };

  group('fromJson returns null when there is nothing to say', () {
    test('null row', () {
      expect(HangoutNudge.fromJson(null), isNull);
    });

    test('zero count', () {
      expect(HangoutNudge.fromJson(row(count: 0)), isNull);
    });

    test('negative count is not rendered as a crowd', () {
      expect(HangoutNudge.fromJson(row(count: -5)), isNull);
    });

    test('missing count', () {
      expect(HangoutNudge.fromJson(row(count: null)), isNull);
    });

    test('empty label — the sentence would have a hole in it', () {
      expect(HangoutNudge.fromJson(row(label: '')), isNull);
    });

    test('whitespace-only label', () {
      expect(HangoutNudge.fromJson(row(label: '   ')), isNull);
    });

    test('missing label', () {
      expect(HangoutNudge.fromJson(row(label: null)), isNull);
    });
  });

  group('fromJson parses a real row', () {
    test('all fields', () {
      final n = HangoutNudge.fromJson(row())!;
      expect(n.nearbyCount, 22);
      expect(n.interestKey, 'nightlife');
      expect(n.interestLabel, 'Nightlife');
      expect(n.interestEmoji, '🌙');
      expect(n.radiusKm, 15);
    });

    test('count arriving as a double survives', () {
      // Postgres ints come back as int, but a json round trip through the
      // platform channel has produced doubles elsewhere in this codebase —
      // see marker_lookup.dart for the bug that caused.
      expect(HangoutNudge.fromJson(row(count: 22.0))!.nearbyCount, 22);
    });

    test('missing emoji is tolerated — event_categories may have none', () {
      final n = HangoutNudge.fromJson(row(emoji: null))!;
      expect(n.interestEmoji, '');
      expect(n.interestLabel, 'Nightlife');
    });

    test('label is trimmed', () {
      expect(
        HangoutNudge.fromJson(row(label: '  Live Music  '))!.interestLabel,
        'Live Music',
      );
    });
  });

  group('copy', () {
    test('headline reads as a fact, not a pitch', () {
      final n = HangoutNudge.fromJson(row())!;
      expect(n.headline, '22 people near you are into Nightlife');
    });

    test('headline uses the real label from event_categories', () {
      final n = HangoutNudge.fromJson(
        row(count: 31, key: 'comedy', label: 'Stand-up Comedy'),
      )!;
      expect(n.headline, '31 people near you are into Stand-up Comedy');
    });

    test('subtitle names the radius so the count is checkable', () {
      expect(HangoutNudge.fromJson(row())!.subtitle, contains('15 km'));
    });

    test('subtitle omits a missing radius rather than saying "0 km"', () {
      final n = HangoutNudge.fromJson(row(radius: 0))!;
      expect(n.subtitle, isNot(contains('0 km')));
      expect(n.subtitle, contains('Pick a spot'));
    });

    test('cta says what happens', () {
      expect(HangoutNudge.fromJson(row())!.ctaLabel, 'Start something');
    });
  });
}
