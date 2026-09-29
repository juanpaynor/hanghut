import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/core/utils/concurrency.dart';

void main() {
  test('visits every item exactly once, in order, with no gaps', () async {
    final items = List.generate(37, (i) => i);
    final seen = <int>[];
    await forEachLimited(items, 6, (i) async {
      seen.add(i);
    });
    expect(seen.length, 37, reason: 'an item was dropped or repeated');
    expect(seen.toSet().length, 37, reason: 'an item was visited twice');
    expect(seen.toSet(), items.toSet());
  });

  test('never exceeds the concurrency cap', () async {
    var inFlight = 0;
    var peak = 0;
    final gates = <Completer<void>>[];

    final run = forEachLimited(List.generate(30, (i) => i), 6, (i) async {
      inFlight++;
      peak = peak > inFlight ? peak : inFlight;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      inFlight--;
    });

    // Let the pool fill, then release everything.
    await Future<void>.delayed(Duration.zero);
    expect(peak, 6, reason: 'pool did not fill to its cap');
    while (gates.length < 30) {
      for (final g in List.of(gates)) {
        if (!g.isCompleted) g.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    for (final g in gates) {
      if (!g.isCompleted) g.complete();
    }
    await run;
    expect(peak, lessThanOrEqualTo(6), reason: 'exceeded the cap');
    expect(inFlight, 0);
  });

  test('a slow item delays only its own worker', () async {
    final order = <int>[];
    await forEachLimited(List.generate(6, (i) => i), 3, (i) async {
      // Item 0 is slow; the others must not queue behind it.
      if (i == 0) await Future<void>.delayed(const Duration(milliseconds: 40));
      order.add(i);
    });
    expect(order.length, 6);
    expect(order.first, isNot(0), reason: 'everything waited on the slow item');
    expect(order.last, anyOf(0, 5));
  });

  test('handles an empty list without starting a worker', () async {
    var called = false;
    await forEachLimited(<int>[], 6, (_) async => called = true);
    expect(called, isFalse);
  });

  test('never starts more workers than there are items', () async {
    var peak = 0;
    var inFlight = 0;
    await forEachLimited(List.generate(2, (i) => i), 50, (i) async {
      inFlight++;
      peak = peak > inFlight ? peak : inFlight;
      await Future<void>.delayed(Duration.zero);
      inFlight--;
    });
    expect(peak, lessThanOrEqualTo(2));
  });

  test('a concurrency of zero still makes progress rather than hanging', () async {
    final seen = <int>[];
    await forEachLimited(List.generate(4, (i) => i), 0, (i) async {
      seen.add(i);
    }).timeout(const Duration(seconds: 2));
    expect(seen.length, 4);
  });

  test('a throwing action surfaces rather than being swallowed', () async {
    expect(
      forEachLimited(List.generate(3, (i) => i), 2, (i) async {
        if (i == 1) throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
  });
}
