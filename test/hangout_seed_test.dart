import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// A suggestion drives a yes/no the user acts on — and "yes" creates a real
/// hangout immediately — so the parse has to refuse anything that cannot make
/// a complete, truthful plan.
void main() {
  final future = DateTime.now().add(const Duration(days: 4));

  Map<String, dynamic> row({
    Object? seedId = 'seed-1',
    Object? slug = 'coffee',
    Object? title = 'Grab coffee',
    Object? emoji = '☕',
    Object? gifQuery = 'coffee with friends',
    Object? venue = 'Yardstick Coffee',
    Object? when,
    Object? lat = 14.5547,
    Object? lng = 121.0244,
    Object? pool = 94,
    Object? going = 0,
    Object? status = 'open',
    Object? response,
    Object? tableId,
  }) => {
        'seed_id': seedId,
        'activity_slug': slug,
        'activity_title': title,
        'emoji': emoji,
        'gif_query': gifQuery,
        'venue_name': venue,
        'latitude': lat,
        'longitude': lng,
        'proposed_at': when ?? future.toIso8601String(),
        'pool_size': pool,
        'going_count': going,
        'status': status,
        'claimed_table_id': tableId,
        'my_response': response,
      };

  group('fromJson refuses an incomplete suggestion', () {
    test('null row', () => expect(HangoutSeed.fromJson(null), isNull));

    test('no activity — the plan has no "what"', () {
      expect(HangoutSeed.fromJson(row(title: '')), isNull);
      expect(HangoutSeed.fromJson(row(title: '   ')), isNull);
    });

    test('no venue — the plan has no "where"', () {
      expect(HangoutSeed.fromJson(row(venue: '')), isNull);
    });

    test('unparseable time — the plan has no "when"', () {
      expect(HangoutSeed.fromJson(row(when: 'not a date')), isNull);
    });

    test('missing id', () {
      expect(HangoutSeed.fromJson(row(seedId: '')), isNull);
    });

    test('null island is not a venue', () {
      // Same guard as the create flows: a hangout at (0,0) is in the Gulf of
      // Guinea and could never be found by anyone.
      expect(HangoutSeed.fromJson(row(lat: 0, lng: 0)), isNull);
    });

    test('missing coordinates', () {
      expect(HangoutSeed.fromJson(row(lat: null)), isNull);
    });

    test('a time already past is not a plan', () {
      final past = DateTime.now().subtract(const Duration(hours: 2));
      expect(HangoutSeed.fromJson(row(when: past.toIso8601String())), isNull);
    });

    test('expired or cancelled status renders nothing', () {
      expect(HangoutSeed.fromJson(row(status: 'expired')), isNull);
      expect(HangoutSeed.fromJson(row(status: 'cancelled')), isNull);
      expect(HangoutSeed.fromJson(row(status: 'something_new')), isNull);
    });
  });

  group('fromJson parses a real suggestion', () {
    test('all fields', () {
      final s = HangoutSeed.fromJson(row())!;
      expect(s.seedId, 'seed-1');
      expect(s.activitySlug, 'coffee');
      expect(s.activityTitle, 'Grab coffee');
      expect(s.venueName, 'Yardstick Coffee');
      expect(s.gifQuery, 'coffee with friends');
      expect(s.poolSize, 94);
      expect(s.isOpen, isTrue);
    });

    test('a claimed suggestion still parses — there is a hangout to join', () {
      final s = HangoutSeed.fromJson(
        row(status: 'claimed', tableId: 'table-9', response: 'in'),
      )!;
      expect(s.status, HangoutSeedStatus.claimed);
      expect(s.claimedTableId, 'table-9');
      expect(s.isOpen, isFalse);
      expect(s.alreadySaidYes, isTrue);
    });

    test('a count arriving as a double survives', () {
      // Platform-channel JSON has produced doubles elsewhere in this codebase
      // — see marker_lookup.dart for the crash that caused.
      expect(HangoutSeed.fromJson(row(pool: 94.0))!.poolSize, 94);
    });
  });

  group('needsAnswer decides whether to ask', () {
    test('open and unanswered — ask', () {
      expect(HangoutSeed.fromJson(row())!.needsAnswer, isTrue);
    });

    test('already said yes — do not ask again', () {
      expect(HangoutSeed.fromJson(row(response: 'in'))!.needsAnswer, isFalse);
    });

    test('already claimed — nothing left to decide', () {
      final s = HangoutSeed.fromJson(row(status: 'claimed', tableId: 't'))!;
      expect(s.needsAnswer, isFalse);
    });
  });

  group('copy', () {
    test('headline names the activity and the place', () {
      expect(
        HangoutSeed.fromJson(row())!.headline,
        'Grab coffee at Yardstick Coffee',
      );
    });

    test('whenLabel leads with the weekday so "soon" is readable', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 10, 9, 10, 0).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Sat 9 Oct, 10am');
    });

    test('whenLabel renders midnight as 12am, not 0am', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 10, 9, 0, 0).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Sat 9 Oct, 12am');
    });

    test('whenLabel renders noon as 12pm and keeps minutes', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 10, 9, 12, 30).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Sat 9 Oct, 12:30pm');
    });

    test('whenLabel does not zero-pad a single-digit day', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 11, 3, 19, 0).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Wed 3 Nov, 7pm');
    });

    test('poolLabel states the nearby crowd when nobody is in yet', () {
      expect(
        HangoutSeed.fromJson(row())!.poolLabel,
        '94 people near you are up for this',
      );
    });

    test('poolLabel switches to commitment once someone says yes', () {
      // Committed company persuades where a headcount does not.
      expect(
        HangoutSeed.fromJson(row(going: 4))!.poolLabel,
        '4 people are already in',
      );
    });

    test('poolLabel is singular for one', () {
      expect(
        HangoutSeed.fromJson(row(going: 1))!.poolLabel,
        '1 person is already in',
      );
    });

    test('poolLabel degrades honestly at zero', () {
      expect(
        HangoutSeed.fromJson(row(pool: 0, going: 0))!.poolLabel,
        'Nobody has made a plan yet',
      );
    });

    test('subtitle says saying yes means hosting it', () {
      expect(
        HangoutSeed.fromJson(row())!.subtitle,
        contains('yours to host'),
      );
    });

    test('subtitle changes once somebody is hosting', () {
      final s = HangoutSeed.fromJson(row(status: 'claimed', tableId: 't'))!;
      expect(s.subtitle, contains('Someone is hosting'));
    });
  });
}
