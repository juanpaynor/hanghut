import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/ticketing/models/event_social_proof.dart';

/// Pure model and copy tests — no rasterising. `Picture.toImage()` hangs in
/// this project's flutter_test environment (proven: three tests, three
/// `TimeoutException after 0:10:00`).
void main() {
  EventSocialProof proof({
    int going = 0,
    int interested = 0,
    List<String> avatars = const [],
    EventViewerState state = EventViewerState.none,
  }) =>
      EventSocialProof(
        goingCount: going,
        interestedCount: interested,
        avatars: avatars,
        viewerState: state,
      );

  group('goingLabel ladder', () {
    test('a real headcount wins', () {
      expect(proof(going: 369, interested: 4).goingLabel, '369 going');
    });

    test('interest is the headline when nobody has bought', () {
      expect(proof(interested: 4).goingLabel, '4 interested');
    });

    test('an untouched event invites rather than reports', () {
      // 75 of 84 upcoming events have sold nothing, so this is the common
      // case and it must not read like a verdict.
      expect(proof().goingLabel, 'Be the first to go');
    });

    test('singular and plural are not special-cased — "1 going" is correct',
        () {
      expect(proof(going: 1).goingLabel, '1 going');
    });
  });

  group('goingLabelCompact', () {
    test('mirrors the full label but fits a card column', () {
      expect(proof(going: 335).goingLabelCompact, '335 going');
      expect(proof(interested: 2).goingLabelCompact, '2 interested');
      expect(proof().goingLabelCompact, 'Be first');
    });
  });

  group('interestedSuffix', () {
    test('shown only alongside a real going count', () {
      expect(proof(going: 10, interested: 3).interestedSuffix, '3 interested');
    });

    test('suppressed when interest IS the headline, to avoid saying it twice',
        () {
      expect(proof(interested: 3).interestedSuffix, isNull);
    });

    test('suppressed when there is no interest', () {
      expect(proof(going: 10).interestedSuffix, isNull);
    });
  });

  group('counts include guests, faces do not', () {
    test('the label reports the full headcount, not the number of faces', () {
      // KOOLCHELLA: 369 people going, 8 of whom have accounts, 3 faces shown.
      // If the label ever followed avatars.length it would read "3 going" on
      // the biggest event in the catalogue.
      final p = proof(going: 369, avatars: ['a', 'b', 'c']);
      expect(p.goingLabel, '369 going');
      expect(p.avatars.length, 3);
    });

    test('a packed event with zero faces still reports its headcount', () {
      // The normal case: every buyer checked out as a guest.
      expect(proof(going: 13).goingLabel, '13 going');
      expect(proof(going: 13).avatars, isEmpty);
    });
  });

  group('isEmpty', () {
    test('true only when there is nothing at all to report', () {
      expect(proof().isEmpty, isTrue);
      expect(proof(going: 1).isEmpty, isFalse);
      expect(proof(interested: 1).isEmpty, isFalse);
    });
  });

  group('canMarkInterested', () {
    test('a ticket holder is already going — nothing to offer', () {
      expect(proof(state: EventViewerState.going).canMarkInterested, isFalse);
    });

    test('someone already interested is not offered it again', () {
      expect(
        proof(state: EventViewerState.interested).canMarkInterested,
        isFalse,
      );
    });

    test('offered to everyone else', () {
      expect(proof().canMarkInterested, isTrue);
    });
  });

  group('fromJson', () {
    test('reads the server shape', () {
      final p = EventSocialProof.fromJson({
        'going_count': 369,
        'interested_count': 4,
        'avatars': ['https://a', 'https://b'],
        'viewer_state': 'interested',
      });
      expect(p.goingCount, 369);
      expect(p.interestedCount, 4);
      expect(p.avatars, ['https://a', 'https://b']);
      expect(p.viewerState, EventViewerState.interested);
    });

    test('drops empty avatar strings rather than rendering blank circles', () {
      final p = EventSocialProof.fromJson({
        'avatars': ['https://a', '', null, 'https://b'],
      });
      expect(p.avatars, ['https://a', 'https://b']);
    });

    test('an absent or unrecognised viewer_state is none, never a crash', () {
      expect(EventSocialProof.fromJson({}).viewerState, EventViewerState.none);
      expect(
        EventSocialProof.fromJson({'viewer_state': 'banana'}).viewerState,
        EventViewerState.none,
      );
    });

    test('a totally empty payload reads as the empty state', () {
      final p = EventSocialProof.fromJson({});
      expect(p.goingCount, 0);
      expect(p.isEmpty, isTrue);
      expect(p.goingLabel, 'Be the first to go');
    });

    test('accepts numeric counts from the wire', () {
      final p = EventSocialProof.fromJson({'going_count': 7.0});
      expect(p.goingCount, 7);
    });
  });

  group('unknown', () {
    test('renders as a plain empty state, which is what a missing RPC gives',
        () {
      expect(EventSocialProof.unknown.isEmpty, isTrue);
      expect(EventSocialProof.unknown.goingLabel, 'Be the first to go');
      expect(EventSocialProof.unknown.canMarkInterested, isTrue);
    });
  });

  group('copyWith + equality', () {
    test('the optimistic toggle produces the interested state', () {
      final before = proof();
      final after = before.copyWith(
        interestedCount: before.interestedCount + 1,
        viewerState: EventViewerState.interested,
      );
      expect(after.interestedCount, 1);
      expect(after.viewerState, EventViewerState.interested);
      expect(after.goingLabel, '1 interested');
    });

    test('equality distinguishes a refetch from our own update', () {
      // didUpdateWidget compares these to decide whether to adopt the
      // server's version; without value equality it would always adopt and
      // clobber the optimistic state mid-write.
      expect(proof(going: 1), equals(proof(going: 1)));
      expect(proof(going: 1), isNot(equals(proof(going: 2))));
      expect(
        proof(state: EventViewerState.none),
        isNot(equals(proof(state: EventViewerState.interested))),
      );
      expect(proof(avatars: ['a']), isNot(equals(proof(avatars: ['b']))));
    });

    test('copyWith leaves untouched fields alone', () {
      final p = proof(going: 5, avatars: ['a'], interested: 2);
      final q = p.copyWith(interestedCount: 3);
      expect(q.goingCount, 5);
      expect(q.avatars, ['a']);
      expect(q.interestedCount, 3);
    });
  });
}
