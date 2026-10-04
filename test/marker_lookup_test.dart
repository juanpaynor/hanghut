import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/map/models/marker_lookup.dart';

/// The field report this file exists for:
///
///   🔖 Marker tapped with index: -1, type: event
///   ❌ Error handling map tap: RangeError (length):
///      Invalid value: Not in inclusive range 0..5: -1
void main() {
  group('markerItem bounds', () {
    final list = ['a', 'b', 'c', 'd', 'e', 'f']; // length 6, as in the report

    test('-1 resolves to null instead of throwing', () {
      // The whole bug. Every tap branch tested `index < list.length` and
      // nothing else, so -1 passed and went straight into list[-1].
      expect(markerItem(list, -1), isNull);
    });

    test('the old condition would have passed -1', () {
      // Guards the guard: if someone reinstates the single-sided test, this
      // documents that it is not equivalent.
      const index = -1;
      expect(index < list.length, isTrue, reason: 'the old check passed');
      expect(markerItem(list, index), isNull, reason: 'the new one does not');
      expect(() => list[index], throwsRangeError);
    });

    test('past the end resolves to null', () {
      expect(markerItem(list, 6), isNull);
      expect(markerItem(list, 999), isNull);
    });

    test('null index resolves to null', () {
      expect(markerItem(list, null), isNull);
    });

    test('both edges of a valid range resolve', () {
      expect(markerItem(list, 0), 'a');
      expect(markerItem(list, 5), 'f');
    });

    test('an empty list resolves nothing, including index 0', () {
      // The state a marker is in after a refetch returns no events.
      expect(markerItem(<String>[], 0), isNull);
    });
  });

  group('markerIndex parsing', () {
    test('reads an int', () {
      expect(markerIndex({'index': 3}), 3);
    });

    test('reads a double — the platform channel sends these', () {
      // One handler used `index is int` and so silently dropped every tap
      // whose index arrived as a double.
      expect(markerIndex({'index': 3.0}), 3);
    });

    test('reads a string', () {
      expect(markerIndex({'index': '3'}), 3);
    });

    test('preserves a negative value rather than hiding it', () {
      // markerIndex must not sanitise: markerItem is what refuses it, and the
      // tap handler logs the -1 so the staleness stays diagnosable.
      expect(markerIndex({'index': -1}), -1);
      expect(markerIndex({'index': '-1'}), -1);
    });

    test('a missing, null or unparseable index is null', () {
      expect(markerIndex({}), isNull);
      expect(markerIndex({'index': null}), isNull);
      expect(markerIndex({'index': 'banana'}), isNull);
      expect(markerIndex(null), isNull);
    });
  });

  group('markerEventId', () {
    test('reads the id a marker carries', () {
      expect(markerEventId({'event_id': 'abc-123'}), 'abc-123');
    });

    test('an empty id is null, so the caller falls back to the index', () {
      expect(markerEventId({'event_id': ''}), isNull);
    });

    test('an absent id is null — venue stacks and tables carry none', () {
      expect(markerEventId({'type': 'stack', 'ids': 'a,b'}), isNull);
      expect(markerEventId(null), isNull);
    });
  });
}
