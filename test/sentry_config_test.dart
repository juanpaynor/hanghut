import 'package:flutter_test/flutter_test.dart';

import 'package:bitemates/core/config/sentry_config.dart';

/// Guards against the one failure mode this config is designed to survive
/// quietly: shipping a release with no DSN.
///
/// `initSentryAndRun` deliberately runs the app and reports nothing when the
/// DSN is unset, so a build with crash reporting silently disabled looks
/// completely healthy — the app starts, no error appears, and you find out
/// months later that the crash you needed was never recorded. That is the right
/// runtime behaviour and the wrong thing to discover after the fact, so the
/// check belongs in CI instead.
void main() {
  group('Sentry DSN', () {
    test('is configured — a release must never ship reporting disabled', () {
      expect(kSentryDsn, isNotEmpty);
      expect(kSentryDsn.startsWith('PASTE_'), isFalse,
          reason: 'The placeholder is still in sentry_config.dart, so crash '
              'reporting will silently disable itself in this build.');
    });

    test('parses as a modern Sentry DSN', () {
      final uri = Uri.parse(kSentryDsn);
      expect(uri.scheme, 'https', reason: 'DSN must be https');
      expect(uri.userInfo, isNotEmpty, reason: 'DSN must carry a public key');
      expect(uri.userInfo, isNot(contains(':')),
          reason: 'A colon means a legacy DSN with a secret half; Sentry '
              'stopped accepting those. Copy the DSN from Client Keys again.');
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(uri.userInfo), isTrue,
          reason: 'Public key should be 32 hex characters');
      expect(uri.host, contains('sentry.io'));
      final projectId = uri.path.replaceAll('/', '');
      expect(int.tryParse(projectId), isNotNull,
          reason: 'The trailing path segment must be a numeric project id');
    });
  });
}
