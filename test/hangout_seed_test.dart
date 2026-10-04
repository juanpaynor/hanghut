import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// An offer drives a yes/no the user acts on, so the parse has to refuse
/// anything that cannot make a complete, truthful offer. A half-parsed one
/// would render the vague prompt this feature exists to replace.
void main() {
  final future = DateTime.now().add(const Duration(days: 4));

  Map<String, dynamic> row({
    Object? seedId = 'seed-1',
    Object? venue = 'Monarch Manila',
    Object? title = 'GB LABRADOR AND THE INGLISHEROS',
    Object? cover,
    Object? going = 0,
    Object? label = 'Stand-up Comedy',
    Object? emoji = '🎤',
    Object? when,
    Object? lat = 14.5547,
    Object? lng = 121.0244,
    Object? pool = 31,
    Object? status = 'open',
    Object? response,
    Object? tableId,
  }) => {
        'seed_id': seedId,
        'category': 'comedy',
        'event_id': 'event-1',
        'event_title': title,
        'cover_image_url': cover,
        'going_count': going,
        'interest_label': label,
        'interest_emoji': emoji,
        'venue_name': venue,
        'latitude': lat,
        'longitude': lng,
        'proposed_at': when ?? future.toIso8601String(),
        'pool_size': pool,
        'status': status,
        'claimed_table_id': tableId,
        'my_response': response,
      };

  group('fromJson refuses an incomplete offer', () {
    test('null row', () => expect(HangoutSeed.fromJson(null), isNull));

    test('no event title — the offer has no "what"', () {
      expect(HangoutSeed.fromJson(row(title: '')), isNull);
      expect(HangoutSeed.fromJson(row(title: '   ')), isNull);
    });

    test('no interest label — nothing to say why it was offered', () {
      expect(HangoutSeed.fromJson(row(label: '  ')), isNull);
    });

    test('unparseable time — the offer has no "when"', () {
      expect(HangoutSeed.fromJson(row(when: 'not a date')), isNull);
    });

    test('missing id', () {
      expect(HangoutSeed.fromJson(row(seedId: '')), isNull);
    });

    test('null island is not a venue', () {
      // Same guard as the create flows: an offer at (0,0) could never be
      // found by anyone.
      expect(HangoutSeed.fromJson(row(lat: 0, lng: 0)), isNull);
    });

    test('missing coordinates', () {
      expect(HangoutSeed.fromJson(row(lat: null)), isNull);
    });

    test('an event that already happened is not an invitation', () {
      final past = DateTime.now().subtract(const Duration(hours: 2));
      expect(HangoutSeed.fromJson(row(when: past.toIso8601String())), isNull);
    });

    test('expired or cancelled status renders nothing', () {
      expect(HangoutSeed.fromJson(row(status: 'expired')), isNull);
      expect(HangoutSeed.fromJson(row(status: 'cancelled')), isNull);
      expect(HangoutSeed.fromJson(row(status: 'something_new')), isNull);
    });
  });

  group('fromJson parses a real offer', () {
    test('all fields', () {
      final s = HangoutSeed.fromJson(row())!;
      expect(s.seedId, 'seed-1');
      expect(s.eventTitle, 'GB LABRADOR AND THE INGLISHEROS');
      expect(s.venueName, 'Monarch Manila');
      expect(s.interestLabel, 'Stand-up Comedy');
      expect(s.poolSize, 31);
      expect(s.status, HangoutSeedStatus.open);
      expect(s.isOpen, isTrue);
    });

    test('a missing cover is null, not an empty string', () {
      // The card branches on null to keep its layout; '' would render a
      // broken image box.
      expect(HangoutSeed.fromJson(row(cover: ''))!.coverImageUrl, isNull);
      expect(HangoutSeed.fromJson(row())!.coverImageUrl, isNull);
      expect(
        HangoutSeed.fromJson(row(cover: 'https://x/y.jpg'))!.coverImageUrl,
        'https://x/y.jpg',
      );
    });

    test('a claimed offer still parses — there is a hangout to join', () {
      final s = HangoutSeed.fromJson(
        row(status: 'claimed', tableId: 'table-9', response: 'in'),
      )!;
      expect(s.status, HangoutSeedStatus.claimed);
      expect(s.claimedTableId, 'table-9');
      expect(s.isOpen, isFalse);
      expect(s.alreadySaidYes, isTrue);
    });
  });

  group('needsAnswer decides whether to ask', () {
    test('open and unanswered — ask', () {
      expect(HangoutSeed.fromJson(row())!.needsAnswer, isTrue);
    });

    test('already said yes — do not ask again', () {
      // Re-asking reads as the app having lost their reply.
      expect(HangoutSeed.fromJson(row(response: 'in'))!.needsAnswer, isFalse);
    });

    test('already claimed — nothing left to decide', () {
      final s = HangoutSeed.fromJson(row(status: 'claimed', tableId: 't'))!;
      expect(s.needsAnswer, isFalse);
    });
  });

  group('copy', () {
    test('headline is the real event name, not a template', () {
      // The invented-title catalogue this replaced could never produce
      // "RUN FOR YOUR LIFE: A Zombie Marathon".
      expect(
        HangoutSeed.fromJson(row())!.headline,
        'GB LABRADOR AND THE INGLISHEROS',
      );
    });

    test('whereAndWhen pairs the date with the venue', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 10, 15, 20, 0).toIso8601String()),
      )!;
      expect(s.whereAndWhen, 'Fri 15 Oct · Monarch Manila');
    });

    test('whenLabel leads with the weekday so "soon" is readable', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 10, 15, 20, 0).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Fri 15 Oct');
    });

    test('whenLabel does not zero-pad a single-digit day', () {
      final s = HangoutSeed.fromJson(
        row(when: DateTime(2027, 11, 3, 19, 0).toIso8601String()),
      )!;
      expect(s.whenLabel, 'Wed 3 Nov');
    });

    test('whereAndWhen omits an empty venue rather than trailing a dot', () {
      final s = HangoutSeed.fromJson(
        row(venue: '', when: DateTime(2027, 10, 15, 20, 0).toIso8601String()),
      )!;
      expect(s.whereAndWhen, 'Fri 15 Oct');
    });

    test('poolLabel states the interested crowd when nobody is in yet', () {
      expect(
        HangoutSeed.fromJson(row())!.poolLabel,
        '31 people near you are into this',
      );
    });

    test('poolLabel switches to commitment once someone says yes', () {
      // Committed company persuades where a demographic count does not.
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

    test('subtitle states the commitment plainly', () {
      expect(
        HangoutSeed.fromJson(row())!.subtitle,
        contains('First to say yes hosts it'),
      );
    });

    test('subtitle changes once somebody is hosting', () {
      final s = HangoutSeed.fromJson(row(status: 'claimed', tableId: 't'))!;
      expect(s.subtitle, contains('Someone is hosting'));
    });
  });
}
