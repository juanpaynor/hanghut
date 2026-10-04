import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/activity/models/invite_rules.dart';

/// The bug these guard: `acceptInvite`/`declineInvite` scoped on
/// `status = 'pending'` alone, so an `invited` row matched zero rows — and a
/// 0-row PostgREST update does not error, so both returned success having
/// saved nothing. The user was told "You're in! 🎉" and was not in.
void main() {
  group('openInviteStatuses', () {
    test('covers both shapes an invite can have', () {
      expect(openInviteStatuses, containsAll(['invited', 'pending']));
    });

    test('the old single-status filter would have missed "invited"', () {
      // Guards the guard. If someone narrows this back to one value, this
      // documents what breaks.
      expect(openInviteStatuses.contains('invited'), isTrue);
      expect(openInviteStatuses.length, 2);
    });

    test('does not include answered states', () {
      for (final answered in ['joined', 'approved', 'attended', 'declined',
        'left', 'no_show', 'interested']) {
        expect(openInviteStatuses, isNot(contains(answered)),
            reason: '$answered is not an open invite');
      }
    });
  });

  group('isOpenInvite', () {
    test('an "invited" row is an invite on its own', () {
      expect(
        isOpenInvite(status: 'invited', namedInInvitedArray: false),
        isTrue,
        reason: 'the array is legacy corroboration, not a requirement',
      );
    });

    test('a "pending" row is an invite ONLY with the legacy array', () {
      // 'pending' is written both by "the host invited me at create time" and
      // by "I asked to join". Only the array separates them.
      expect(isOpenInvite(status: 'pending', namedInInvitedArray: true), isTrue);
      expect(
        isOpenInvite(status: 'pending', namedInInvitedArray: false),
        isFalse,
        reason: 'my own join request must not offer me an Accept button',
      );
    });

    test('answered and unknown states are not invites', () {
      for (final s in ['joined', 'approved', 'attended', 'declined', 'left',
        'interested', 'banana', '', null]) {
        expect(
          isOpenInvite(status: s, namedInInvitedArray: true),
          isFalse,
          reason: '$s must not read as an open invite even with the array',
        );
      }
    });
  });

  group('isLiveInvite', () {
    final now = DateTime(2026, 10, 5, 12, 0);

    test('an open hangout in the future is live', () {
      expect(
        isLiveInvite(
          hangoutStatus: 'open',
          startsAt: now.add(const Duration(days: 2)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a past hangout is not an invitation any more', () {
      expect(
        isLiveInvite(
          hangoutStatus: 'open',
          startsAt: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a cancelled or completed hangout is dead even if still upcoming', () {
      // expire_past_hangouts() uses 'completed'; a host can 'cancel'. Both must
      // drop out, and the time check alone would not catch either.
      for (final s in ['cancelled', 'completed', 'full']) {
        expect(
          isLiveInvite(
            hangoutStatus: s,
            startsAt: now.add(const Duration(days: 2)),
            now: now,
          ),
          isFalse,
          reason: 'status $s should not be offered',
        );
      }
    });

    test('a missing date is not live — the map cannot place it either', () {
      expect(
        isLiveInvite(hangoutStatus: 'open', startsAt: null, now: now),
        isFalse,
      );
    });

    test('the status check and the time check catch different things', () {
      // Neither alone is sufficient: this row passes on time but fails status.
      final upcomingButCancelled = isLiveInvite(
        hangoutStatus: 'cancelled',
        startsAt: now.add(const Duration(days: 1)),
        now: now,
      );
      // ...and this one passes on status but fails on time.
      final openButPast = isLiveInvite(
        hangoutStatus: 'open',
        startsAt: now.subtract(const Duration(days: 1)),
        now: now,
      );
      expect(upcomingButCancelled, isFalse);
      expect(openButPast, isFalse);
    });
  });
}
