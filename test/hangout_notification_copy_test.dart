import 'package:bitemates/core/services/table_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The old follower notification read:
///   "Miguel Dadivas just created "Miguel Dadivas wants to Network" — join now!"
/// — the host's name three times, and no time or place. 10% were opened.
/// The body now answers "when", which is the part you cannot act without.
void main() {
  // A Tuesday, mid-afternoon.
  final now = DateTime(2026, 9, 29, 14, 0);

  String label(DateTime d) => TableService.whenLabel(d, now: now);

  test('an evening hangout today reads as Tonight', () {
    expect(label(DateTime(2026, 9, 29, 19, 0)), 'Tonight at 7:00 PM');
  });

  test('a morning hangout today reads as Today, not Tonight', () {
    expect(label(DateTime(2026, 9, 29, 9, 30)), 'Today at 9:30 AM');
  });

  test('5pm is the Tonight boundary', () {
    expect(label(DateTime(2026, 9, 29, 16, 59)), startsWith('Today'));
    expect(label(DateTime(2026, 9, 29, 17, 0)), startsWith('Tonight'));
  });

  test('just past midnight is Tomorrow, not Tonight', () {
    // The trap: 00:30 is a later *instant* but a different calendar day.
    expect(label(DateTime(2026, 9, 30, 0, 30)), 'Tomorrow at 12:30 AM');
  });

  test('later this week names the weekday', () {
    expect(label(DateTime(2026, 10, 2, 20, 0)), 'Fri at 8:00 PM');
  });

  test('beyond a week falls back to a date', () {
    expect(label(DateTime(2026, 10, 20, 20, 0)), 'Oct 20 at 8:00 PM');
  });

  test('exactly 7 days out is a date, not a weekday (ambiguous otherwise)', () {
    expect(label(DateTime(2026, 10, 6, 20, 0)), 'Oct 6 at 8:00 PM');
  });
}
