import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Sentry DSN — Sentry → Settings → Projects → flutter → Client Keys (DSN).
///
/// A Dart constant on purpose, NOT read from `.env`. `.env` is gitignored
/// (`.gitignore:63`) yet declared as a bundled asset (`pubspec.yaml:129`), and
/// `main()` explicitly tolerates it being absent — "expected for release builds
/// where .env is gitignored". Sourcing the DSN from there means crash reporting
/// silently switches itself off on any build made from a clean checkout, which
/// is precisely the build whose crashes matter. It also would not survive a
/// Shorebird patch, which ships Dart only and no assets.
///
/// A DSN is not a credential: it is write-only ingest, designed to ship inside
/// client binaries. CI can still override it with
/// `--dart-define=SENTRY_DSN=...`.
const String kSentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://ac01e5c3ed9beba4b181cc7ff0a42f5a@o4512054853763072.ingest.us.sentry.io/4512054859726848',
);

bool get _dsnConfigured =>
    kSentryDsn.isNotEmpty && !kSentryDsn.startsWith('PASTE_');

/// Boots Sentry and then runs the app.
///
/// [appRunner] is the whole of startup, not just `runApp`, so a crash in
/// Supabase or Firebase initialisation is reported too — those run before the
/// first frame, where a failure is otherwise invisible.
///
/// With no DSN configured this simply runs the app and reports nothing, so a
/// fresh clone or a fork never posts to someone else's project.
Future<void> initSentryAndRun(Future<void> Function() appRunner) async {
  if (!_dsnConfigured) {
    if (kDebugMode) {
      debugPrint('⚠️ Sentry DSN not set — crash reporting disabled.');
    }
    await appRunner();
    return;
  }

  final dist = await _shorebirdDist();

  await SentryFlutter.init(
    (options) {
      options.dsn = kSentryDsn;
      options.environment = kReleaseMode ? 'production' : 'development';

      // Which Shorebird patch is running. Sentry derives `release` from the
      // bundle version, which a patch does NOT change — so without this every
      // crash from every patch of a given build lands in one bucket and there
      // is no way to see which patch introduced it, or to roll the right one
      // back.
      options.dist = dist;

      // Crash analytics, not APM. Performance tracing samples every
      // transaction and would burn the quota for data nobody is reading yet;
      // turn it up deliberately if and when someone wants it.
      options.tracesSampleRate = 0.0;

      // Breadcrumbs are what make a crash readable — the screens and taps that
      // led to it. Keep them; drop the noisy ones.
      options.maxBreadcrumbs = 50;

      // Debug builds DO send, tagged `development` above — otherwise the
      // "throw a test exception" verification step silently does nothing and
      // you cannot tell a working setup from a broken one. If dev noise gets
      // annoying, mute the `development` environment in Sentry's own settings
      // rather than changing code: that decision belongs server-side, where it
      // takes effect without a rebuild.
      options.debug = false;
    },
    appRunner: appRunner,
  );
}

/// `patch<N>` when running Shorebird-patched code, otherwise `base`.
///
/// Wrapped: the updater is absent in debug and in any build not produced by
/// `shorebird release`, and a missing patch number must never stop the app
/// from starting.
Future<String> _shorebirdDist() async {
  try {
    final updater = ShorebirdUpdater();
    final patch = await updater.readCurrentPatch();
    return patch == null ? 'base' : 'patch${patch.number}';
  } catch (_) {
    return 'base';
  }
}
