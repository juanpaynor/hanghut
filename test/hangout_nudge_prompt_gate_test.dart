import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitemates/core/services/hangout_nudge_service.dart';

/// The prompt interrupts the user on the app's landing screen, so the gate
/// that decides whether to show it is the part that must not be wrong. These
/// tests pin the cap and the cooldown independently, because either one
/// failing open produces the behaviour users uninstall over.
void main() {
  const lastShownKey = 'hangout_nudge_prompt_last_shown_ms';
  const shownCountKey = 'hangout_nudge_prompt_shown_count';

  int msAgo(Duration d) =>
      DateTime.now().subtract(d).millisecondsSinceEpoch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('shouldShowPrompt', () {
    test('shows on a fresh install', () async {
      expect(await HangoutNudgeService().shouldShowPrompt(), isTrue);
    });

    test('does not show again inside the cooldown', () async {
      SharedPreferences.setMockInitialValues({
        shownCountKey: 1,
        lastShownKey: msAgo(const Duration(days: 2)),
      });
      expect(await HangoutNudgeService().shouldShowPrompt(), isFalse);
    });

    test('shows again once the cooldown has passed', () async {
      SharedPreferences.setMockInitialValues({
        shownCountKey: 1,
        lastShownKey: msAgo(const Duration(days: 8)),
      });
      expect(await HangoutNudgeService().shouldShowPrompt(), isTrue);
    });

    test('the cooldown boundary is inclusive', () async {
      SharedPreferences.setMockInitialValues({
        shownCountKey: 1,
        lastShownKey: msAgo(HangoutNudgeService.cooldown),
      });
      expect(await HangoutNudgeService().shouldShowPrompt(), isTrue);
    });

    test('stops forever at maxShows, however long ago', () async {
      SharedPreferences.setMockInitialValues({
        shownCountKey: HangoutNudgeService.maxShows,
        lastShownKey: msAgo(const Duration(days: 365)),
      });
      expect(await HangoutNudgeService().shouldShowPrompt(), isFalse);
    });

    test('a count above maxShows also stops it', () async {
      // Defensive: suppressPromptPermanently writes exactly maxShows, but a
      // future change writing more must not wrap around to showing again.
      SharedPreferences.setMockInitialValues({
        shownCountKey: HangoutNudgeService.maxShows + 5,
        lastShownKey: 0,
      });
      expect(await HangoutNudgeService().shouldShowPrompt(), isFalse);
    });
  });

  group('markPromptShown', () {
    test('increments the count and stamps the time', () async {
      final service = HangoutNudgeService();
      await service.markPromptShown();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(shownCountKey), 1);
      expect(prefs.getInt(lastShownKey), isNotNull);
      // And the cooldown is now in force.
      expect(await service.shouldShowPrompt(), isFalse);
    });

    test('three shows exhaust the cap', () async {
      final service = HangoutNudgeService();
      for (var i = 0; i < HangoutNudgeService.maxShows; i++) {
        await service.markPromptShown();
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(shownCountKey), HangoutNudgeService.maxShows);

      // Even with the cooldown fully elapsed, the cap holds.
      await prefs.setInt(lastShownKey, msAgo(const Duration(days: 400)));
      expect(await service.shouldShowPrompt(), isFalse);
    });
  });

  group('suppressPromptPermanently', () {
    test('an explicit "Not now" is final, not merely cooled down', () async {
      final service = HangoutNudgeService();
      await service.suppressPromptPermanently();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(lastShownKey, msAgo(const Duration(days: 400)));

      expect(await service.shouldShowPrompt(), isFalse);
    });
  });
}
