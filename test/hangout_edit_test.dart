import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/map/models/hangout_edit.dart';

/// Saving an edit pushes every committed member when — and only when — the
/// time or the place is sent. So the diff is not a convenience: a field that
/// leaks through unchanged notifies a group of six for nothing, and a field
/// that fails to go through leaves people heading to the wrong place.
void main() {
  final when = DateTime(2026, 10, 11, 16, 0);

  HangoutEditDiff diff({
    String title = 'Play something at Polo Club Tennis Courts',
    String description = '',
    DateTime? dateTime,
    int maxGuests = 6,
    String? venueName,
    String? venueAddress,
    double? venueLat,
    double? venueLng,
  }) => HangoutEditDiff.between(
    originalTitle: 'Play something at Polo Club Tennis Courts',
    currentTitle: title,
    originalDescription: '',
    currentDescription: description,
    originalDateTime: when,
    currentDateTime: dateTime ?? when,
    originalMaxGuests: 6,
    currentMaxGuests: maxGuests,
    newVenueName: venueName,
    newVenueAddress: venueAddress,
    newVenueLat: venueLat,
    newVenueLng: venueLng,
  );

  group('an untouched sheet sends nothing', () {
    test('every field equal to its original', () {
      final d = diff();
      expect(d.isEmpty, isTrue);
      expect(d.isNotEmpty, isFalse);
      expect(d.notifiesMembers, isFalse);
      expect(d.title, isNull);
      expect(d.datetime, isNull);
      expect(d.locationName, isNull);
      expect(d.maxGuests, isNull);
    });

    test('whitespace around an unchanged title is not a change', () {
      expect(
        diff(title: '  Play something at Polo Club Tennis Courts  ').isEmpty,
        isTrue,
      );
    });
  });

  group('a title fix must not push the group', () {
    test('title alone leaves time and place null', () {
      final d = diff(title: 'Tennis at Polo Club');
      expect(d.title, 'Tennis at Polo Club');
      expect(d.isNotEmpty, isTrue);
      // The whole reason this class exists.
      expect(d.notifiesMembers, isFalse);
      expect(d.datetime, isNull);
      expect(d.locationName, isNull);
    });

    test('notes alone do not push either', () {
      final d = diff(description: 'Bring a racket');
      expect(d.description, 'Bring a racket');
      expect(d.notifiesMembers, isFalse);
    });

    test('capacity alone does not push', () {
      final d = diff(maxGuests: 10);
      expect(d.maxGuests, 10);
      expect(d.notifiesMembers, isFalse);
    });
  });

  group('title cannot be blanked', () {
    // `tables.title` is NOT NULL, and a nameless hangout is not a thing to
    // offer a host — so an emptied field reads as "unchanged", not "clear it".
    test('empty title is treated as unchanged', () {
      expect(diff(title: '').title, isNull);
      expect(diff(title: '   ').title, isNull);
      expect(diff(title: '').isEmpty, isTrue);
    });
  });

  group('notes CAN be cleared', () {
    test('emptying a description that had text is a real change', () {
      final d = HangoutEditDiff.between(
        originalTitle: 'T',
        currentTitle: 'T',
        originalDescription: 'Bring a racket',
        currentDescription: '',
        originalDateTime: when,
        currentDateTime: when,
        originalMaxGuests: 6,
        currentMaxGuests: 6,
      );
      expect(d.description, '');
      expect(d.isNotEmpty, isTrue);
      expect(d.notifiesMembers, isFalse);
    });
  });

  group('the venue is one unit', () {
    test('a full pick sends name, both coordinates and the address', () {
      final d = diff(
        venueName: 'Yardstick Coffee',
        venueAddress: '106 Esteban, Legazpi Village, Makati',
        venueLat: 14.5547,
        venueLng: 121.0244,
      );
      expect(d.locationName, 'Yardstick Coffee');
      expect(d.latitude, 14.5547);
      expect(d.longitude, 121.0244);
      expect(d.venueAddress, '106 Esteban, Legazpi Village, Makati');
      expect(d.venueChanged, isTrue);
      expect(d.notifiesMembers, isTrue);
    });

    test('a name with no coordinates moves nothing', () {
      // This is exactly how a hangout ends up pinned where nobody agreed:
      // the label changes and the pin does not.
      final d = diff(venueName: 'Yardstick Coffee');
      expect(d.locationName, isNull);
      expect(d.latitude, isNull);
      expect(d.venueChanged, isFalse);
      expect(d.isEmpty, isTrue);
    });

    test('half a coordinate pair moves nothing', () {
      expect(
        diff(venueName: 'Somewhere', venueLat: 14.55).locationName,
        isNull,
      );
      expect(
        diff(venueName: 'Somewhere', venueLng: 121.02).locationName,
        isNull,
      );
    });

    test('coordinates with no name move nothing', () {
      final d = diff(venueLat: 14.5547, venueLng: 121.0244);
      expect(d.latitude, isNull);
      expect(d.isEmpty, isTrue);
    });

    test('the null island is refused', () {
      // (0, 0) is in the Gulf of Guinea. This editor is the repair tool for
      // the hangouts already stuck there; it must never create another.
      final d = diff(venueName: 'Nowhere', venueLat: 0, venueLng: 0);
      expect(d.locationName, isNull);
      expect(d.latitude, isNull);
      expect(d.isEmpty, isTrue);
    });

    test('a pick with no address clears the old one rather than keeping it', () {
      // The pin moved, so the stored street address now describes the previous
      // place. Empty is correct; stale is a wrong address people act on.
      final d = diff(
        venueName: 'Polo Club Tennis Courts',
        venueAddress: null,
        venueLat: 14.542365,
        venueLng: 121.038858,
      );
      expect(d.venueAddress, '');
      expect(d.locationName, 'Polo Club Tennis Courts');
    });
  });

  group('time changes push', () {
    test('a new time is sent and notifies', () {
      final later = DateTime(2026, 10, 11, 18, 30);
      final d = diff(dateTime: later);
      expect(d.datetime, later);
      expect(d.timeChanged, isTrue);
      expect(d.notifiesMembers, isTrue);
    });

    test('the same instant is not a change', () {
      expect(diff(dateTime: DateTime(2026, 10, 11, 16, 0)).datetime, isNull);
    });

    test('place and time together still read as one notification', () {
      final d = diff(
        dateTime: DateTime(2026, 10, 12, 9, 0),
        venueName: 'Yardstick Coffee',
        venueAddress: 'Makati',
        venueLat: 14.5547,
        venueLng: 121.0244,
      );
      expect(d.timeChanged, isTrue);
      expect(d.venueChanged, isTrue);
      expect(d.notifiesMembers, isTrue);
    });
  });
}
