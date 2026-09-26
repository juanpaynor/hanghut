import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/map/models/hangout_social_proof.dart';

HangoutSocialProof proof({
  int going = 0,
  int interested = 0,
  int occupied = 1,
  int max = 4,
  bool isHost = false,
  String viewer = 'none',
  List<String> avatars = const [],
}) {
  return HangoutSocialProof.fromJson({
    'going_count': going,
    'interested_count': interested,
    'occupied': occupied,
    'max_guests': max,
    'is_host': isHost,
    'avatars': avatars,
    'viewer_state': viewer,
  });
}

void main() {
  group('going label', () {
    test('an empty hangout tells a visitor they would be first', () {
      expect(proof().goingLabel, 'Be the first to join');
    });

    test('an empty hangout does NOT tell the host to join their own hangout', () {
      expect(proof(isHost: true, viewer: 'host').goingLabel,
          'No one has joined yet');
    });

    test('the host row never counts as someone going', () {
      // occupied 1 = the host alone; going_count is guests only.
      expect(proof(going: 0, occupied: 1).isEmpty, isTrue);
    });

    test('counts guests', () {
      expect(proof(going: 1, occupied: 2).goingLabel, '1 going');
      expect(proof(going: 3, occupied: 4).goingLabel, '3 going');
    });

    test('interest is the headline only while nobody has actually joined', () {
      expect(proof(interested: 2).goingLabel, '2 interested');
      expect(proof(going: 2, interested: 3, occupied: 3).goingLabel, '2 going');
      expect(proof(going: 2, interested: 3, occupied: 3).interestedSuffix,
          '3 interested');
      expect(proof(interested: 2).interestedSuffix, isNull);
    });
  });

  group('compact label', () {
    test('stays short enough for a feed card trailing column', () {
      expect(proof().goingLabelCompact, 'Be first');
      expect(proof(isHost: true, viewer: 'host').goingLabelCompact,
          'No one yet');
      expect(proof(going: 3, occupied: 4).goingLabelCompact, '3 going');
      expect(proof(interested: 2).goingLabelCompact, '2 interested');
    });

    test('never exceeds the width budget the feed card has', () {
      // ~14 chars is what fits beside a Join button on a 390pt screen.
      for (final p in [
        proof(),
        proof(isHost: true, viewer: 'host'),
        proof(going: 12, occupied: 13),
        proof(interested: 7),
      ]) {
        expect(p.goingLabelCompact.length, lessThanOrEqualTo(14),
            reason: p.goingLabelCompact);
      }
    });
  });

  group('needs N more', () {
    test('asks for the gap on a normal hangout', () {
      expect(proof(going: 0, occupied: 1, max: 4).needsMoreLabel,
          'Needs 3 more');
      expect(proof(going: 2, occupied: 3, max: 4).needsMoreLabel,
          'Needs 1 more');
    });

    test('stays silent on legacy 30-capacity hangouts', () {
      // "Needs 29 more" reads as "nobody is coming" — the opposite of a nudge.
      expect(proof(going: 0, occupied: 1, max: 30).needsMoreLabel, isNull);
    });

    test('stays silent when full', () {
      final full = proof(going: 3, occupied: 4, max: 4);
      expect(full.isFull, isTrue);
      expect(full.needsMoreLabel, isNull);
    });

    test('never reports negative spots when over capacity', () {
      final over = proof(going: 6, occupied: 7, max: 4);
      expect(over.spotsLeft, 0);
      expect(over.isFull, isTrue);
      expect(over.needsMoreLabel, isNull);
    });

    test('an unknown max_guests is not an ask', () {
      expect(proof(max: 0, occupied: 0).needsMoreLabel, isNull);
      expect(proof(max: 0, occupied: 0).spotsLeft, 0);
    });
  });

  group('viewer state', () {
    test('someone interested can still upgrade to joining', () {
      final p = proof(viewer: 'interested');
      expect(p.viewerState, HangoutViewerState.interested);
      expect(p.canJoin, isTrue);
      expect(p.canMarkInterested, isFalse);
    });

    test('someone already going cannot join or mark interested', () {
      final p = proof(viewer: 'going', going: 1, occupied: 2);
      expect(p.canJoin, isFalse);
      expect(p.canMarkInterested, isFalse);
    });

    test('a pending request is neither', () {
      final p = proof(viewer: 'pending');
      expect(p.canJoin, isFalse);
      expect(p.canMarkInterested, isFalse);
    });

    test('unknown states degrade to none rather than throwing', () {
      expect(proof(viewer: 'something_new').viewerState,
          HangoutViewerState.none);
    });
  });

  group('parsing', () {
    test('survives a completely empty payload', () {
      final p = HangoutSocialProof.fromJson({});
      expect(p.goingCount, 0);
      expect(p.avatars, isEmpty);
      expect(p.viewerState, HangoutViewerState.none);
      expect(p.needsMoreLabel, isNull);
      expect(p.goingLabel, 'Be the first to join');
    });

    test('drops null and empty avatar urls', () {
      final p = proof(avatars: const ['a.jpg', '', 'b.jpg']);
      expect(p.avatars, ['a.jpg', 'b.jpg']);
    });

    test('unknown is a safe placeholder', () {
      expect(HangoutSocialProof.unknown.goingLabel, 'Be the first to join');
      expect(HangoutSocialProof.unknown.needsMoreLabel, isNull);
    });
  });
}
