/// Human copy for the `criteria` jsonb on a partner badge — "what did I do to
/// get this?".
///
/// Every branch below mirrors `creator_badge_qualifying_emails` in Postgres,
/// including its `coalesce` defaults, so the sentence a user reads matches the
/// SQL that actually awarded the badge. If web extends the engine, this needs
/// extending with it — the constraint currently allows 11 types.
///
/// Deliberately vague where the engine references a row we would need another
/// query to name (a specific event, a ticket tier): a slightly generic sentence
/// beats a network round trip inside a bottom sheet, and beats inventing a name.
class CreatorBadgeCriteria {
  /// Past-tense phrase describing what the holder did, e.g. "Turned up to 3 of
  /// their events". [grantType] wins when the badge was handed out directly —
  /// a manual grant has criteria that never ran.
  static String earnedSummary(
    Map<String, dynamic> criteria, {
    String? grantType,
  }) {
    if (grantType == 'manual') return 'Hand-picked by the organiser';
    return _phrase(criteria, past: true);
  }

  /// Imperative phrase describing what it takes, e.g. "Turn up to 3 of their
  /// events" — for badges not yet earned.
  static String requirementSummary(Map<String, dynamic> criteria) =>
      _phrase(criteria, past: false);

  static String _phrase(Map<String, dynamic> criteria, {required bool past}) {
    final type = criteria['type'] as String?;
    final params = criteria['params'] is Map
        ? Map<String, dynamic>.from(criteria['params'] as Map)
        : const <String, dynamic>{};

    int intParam(String key, int fallback) {
      final v = params[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    switch (type) {
      case 'attendance_count':
        // Engine counts DISTINCT events checked into.
        final n = intParam('n', 1);
        final verb = past ? 'Turned up to' : 'Turn up to';
        return n <= 1
            ? '$verb one of their events'
            : '$verb $n of their events';

      case 'checkin_count':
        // Total check-ins, not distinct events — repeat visits count.
        final n = intParam('n', 1);
        final verb = past ? 'Checked in' : 'Check in';
        return n <= 1 ? '$verb at their door' : '$verb $n times with them';

      case 'spend_total':
        final amount = params['amount'];
        final verb = past ? 'Spent' : 'Spend';
        return '$verb ${_peso(amount)} with them';

      case 'specific_event':
        final attended = (params['mode'] as String? ?? 'attended') == 'attended';
        if (attended) return past ? 'Was there on the night' : 'Be there';
        return past ? 'Bought a ticket to it' : 'Buy a ticket to it';

      case 'first_n_buyers':
        final n = intParam('n', 0);
        final byEvent = (params['scope'] as String? ?? 'partner') == 'event';
        final where = byEvent ? 'for this event' : 'ever';
        if (n <= 1) {
          return past
              ? 'Their very first buyer $where'
              : 'Be their first buyer $where';
        }
        return past
            ? 'One of their first $n buyers $where'
            : 'Be one of their first $n buyers $where';

      case 'group_buyer':
        final n = intParam('min_quantity', 2);
        return past
            ? 'Brought a group — $n tickets in one order'
            : 'Bring a group — $n tickets in one order';

      case 'streak_months':
        final n = intParam('n', 2);
        return past
            ? 'Came back $n months running'
            : 'Come back $n months running';

      case 'event_count_purchased':
        final n = intParam('n', 2);
        final verb = past ? 'Bought tickets to' : 'Buy tickets to';
        return '$verb $n of their events';

      case 'tier_purchased':
        return past
            ? 'Bought a particular ticket tier'
            : 'Buy a particular ticket tier';

      case 'customer_segment':
        final segment = (params['segment'] as String?)?.trim();
        if (segment == null || segment.isEmpty) {
          return past ? 'Recognised by the organiser' : 'Earn their recognition';
        }
        return past
            ? 'Recognised as a ${segment.toLowerCase()} customer'
            : 'Become a ${segment.toLowerCase()} customer';

      case 'manual_grant':
        return 'Hand-picked by the organiser';

      default:
        // An unknown type means web shipped a criterion this build predates.
        // Say nothing rather than guess — callers hide the row on empty.
        return '';
    }
  }

  /// Peso amounts with thousands separators. Falls back to a bare label rather
  /// than printing a broken figure when the param is missing or unparseable.
  static String _peso(dynamic amount) {
    num? value;
    if (amount is num) {
      value = amount;
    } else if (amount is String) {
      value = num.tryParse(amount);
    }
    if (value == null) return 'enough';

    final whole = value.round();
    final digits = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '₱$buf';
  }
}
