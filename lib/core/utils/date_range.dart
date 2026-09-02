import 'package:intl/intl.dart';

/// Helpers for displaying an event that may span more than one calendar day.
///
/// Times are compared in the device's local zone (the stored values are UTC
/// timestamptz), matching how the rest of the app renders event times.

/// True when [end] falls on a later calendar day than [start]. False when [end]
/// is null, equal, or on the same day (an event that merely runs a few hours
/// past midnight into the same listing is still single-day if end <= start day).
bool isMultiDayRange(DateTime start, DateTime? end) {
  if (end == null) return false;
  final s = start.toLocal();
  final e = end.toLocal();
  if (!e.isAfter(s)) return false;
  return e.year != s.year || e.month != s.month || e.day != s.day;
}

/// A compact date span for a multi-day event:
///   same month → "Aug 29 – 30"
///   cross-month → "Aug 29 – Sep 1"
///   cross-year → "Dec 31, 2026 – Jan 1, 2027"
/// Only meaningful when [isMultiDayRange] is true for the same pair.
String formatDateRange(DateTime start, DateTime end) {
  final s = start.toLocal();
  final e = end.toLocal();
  if (s.year != e.year) {
    return '${DateFormat('MMM d, y').format(s)} – ${DateFormat('MMM d, y').format(e)}';
  }
  if (s.month == e.month) {
    return '${DateFormat('MMM d').format(s)} – ${DateFormat('d').format(e)}';
  }
  return '${DateFormat('MMM d').format(s)} – ${DateFormat('MMM d').format(e)}';
}

/// Same as [formatDateRange] but with the START time appended, e.g.
/// "Aug 29 – 30 · 7:00 PM" — so a multi-day event still shows when it kicks off.
String formatDateRangeWithTime(DateTime start, DateTime end) =>
    '${formatDateRange(start, end)} · ${DateFormat('h:mm a').format(start.toLocal())}';
