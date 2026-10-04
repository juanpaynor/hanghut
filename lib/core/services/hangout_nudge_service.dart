import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';

/// Fetches the "why would I start one" nudge.
///
/// One RPC, one row, aggregate only. See [HangoutNudge] for why it carries no
/// identities and `get_hangout_nudge()` for the query.
class HangoutNudgeService {
  /// Cached for the process lifetime after the first successful fetch.
  ///
  /// The nudge is a slowly-moving fact about the neighbourhood, and the tab it
  /// sits on is rebuilt on every pull-to-refresh and every tab switch. Without
  /// this, a 10 ms query runs on every one of those for a sentence that cannot
  /// have changed. `_fetched` is separate from `_cached` so a legitimate empty
  /// result (the geographically isolated user) is remembered too, instead of
  /// being retried forever.
  static HangoutNudge? _cached;
  static bool _fetched = false;

  /// Drops the cache so the next [fetch] hits the server.
  ///
  /// Called after the user creates a hangout: they are now "busy" and the RPC
  /// will correctly suppress the nudge, but only if we ask it again.
  static void invalidate() {
    _cached = null;
    _fetched = false;
  }

  /// The nudge, or null when there is nothing worth saying.
  ///
  /// Null is the normal outcome in several real cases, all of which must
  /// render as "no card" rather than as an error: the user shares no location,
  /// has no taste signal yet, has nobody within the radius (one real user has
  /// zero), is already in an upcoming hangout, or the pool is below
  /// `nudge_min_pool`.
  ///
  /// Never throws. A nudge is an enhancement to a screen that has to work
  /// without it, so a failure here degrades to the plain empty state — the
  /// same reason `get_event_social_proof` being absent only logged a warning.
  Future<HangoutNudge?> fetch({bool force = false}) async {
    if (_fetched && !force) return _cached;
    try {
      final rows = await SupabaseConfig.client.rpc('get_hangout_nudge');
      // A set-returning function comes back as a list; it returns at most one
      // row, and zero rows is the ordinary "nothing to say" answer.
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      _cached = HangoutNudge.fromJson(
        row is Map ? Map<String, dynamic>.from(row) : null,
      );
      _fetched = true;
      return _cached;
    } catch (e) {
      debugPrint('⚠️ get_hangout_nudge failed: $e');
      // Deliberately not setting _fetched: a transient failure should be
      // retried on the next build, unlike a genuine empty result.
      return null;
    }
  }

  // ─── The one-time prompt ───────────────────────────

  static const _lastShownKey = 'hangout_nudge_prompt_last_shown_ms';
  static const _shownCountKey = 'hangout_nudge_prompt_shown_count';

  /// How long before the prompt may reappear.
  static const Duration cooldown = Duration(days: 7);

  /// Total times the prompt will EVER be shown.
  ///
  /// Capped rather than cooled down forever: someone who has declined three
  /// times has answered the question, and a prompt that keeps coming back is
  /// the thing users uninstall over. The map banner stays available for
  /// anyone who changes their mind, so the cap costs us no reach.
  static const int maxShows = 3;

  /// Whether to interrupt the user with the modal right now.
  ///
  /// Deliberately conservative — it is an interruption on the app's landing
  /// screen, so every condition has to pass: we have something real to say,
  /// it has been [cooldown] since the last one, and we have not already
  /// asked [maxShows] times. Any storage failure returns false; a prompt that
  /// cannot verify its own cooldown must not show.
  Future<bool> shouldShowPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(_shownCountKey) ?? 0) >= maxShows) return false;
      final last = prefs.getInt(_lastShownKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      return elapsed >= cooldown.inMilliseconds;
    } catch (e) {
      debugPrint('⚠️ hangout nudge prompt gate failed: $e');
      return false;
    }
  }

  /// Records that the prompt was shown, whatever the user then did with it.
  ///
  /// Called at show time rather than on a specific dismissal path, because a
  /// barrier tap runs no callback — the same reason `_checkAdminPopups`
  /// marks seen after the await rather than in `onDismissed`.
  Future<void> markPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastShownKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt(
        _shownCountKey,
        (prefs.getInt(_shownCountKey) ?? 0) + 1,
      );
    } catch (e) {
      debugPrint('⚠️ could not record hangout nudge prompt: $e');
    }
  }

  /// Stops the prompt for good — the user said no thanks.
  Future<void> suppressPromptPermanently() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_shownCountKey, maxShows);
    } catch (e) {
      debugPrint('⚠️ could not suppress hangout nudge prompt: $e');
    }
  }
}
