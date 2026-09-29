import 'dart:math';

/// Runs [action] over [items] with at most [concurrency] running at once.
///
/// `Future.wait(items.map(...))` starts every item in the same tick. For work
/// that holds memory while it runs — decoding images, building bitmaps — that
/// turns a long list into a proportional memory spike, on the devices least
/// able to absorb it. A small pool keeps the peak flat and barely changes
/// wall-clock for IO-bound work.
///
/// Every item is visited exactly once. Each is awaited individually, so a slow
/// item delays only its own worker, and a throwing [action] is surfaced rather
/// than swallowed — callers doing best-effort work should catch inside
/// [action], as the marker generators do.
Future<void> forEachLimited<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) action,
) async {
  if (items.isEmpty) return;
  final workers = min(max(1, concurrency), items.length);

  // Shared cursor. `next++` needs no lock: an isolate runs one statement at a
  // time, so no two workers can read the same index.
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      await action(items[i]);
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
}
