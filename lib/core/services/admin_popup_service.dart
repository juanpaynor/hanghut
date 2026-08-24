import 'package:bitemates/core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminPopupService {
  static const String _seenPrefix = 'popup_seen_';

  /// Safety cap so a mistake on the admin side can never trap a user behind a
  /// wall of modals on a single launch.
  static const int _maxPerLaunch = 3;

  /// Fetches the active popups the user is eligible to see this launch, in the
  /// order they should be shown (a queue — the caller displays them one after
  /// another): highest `priority` first, newest as the tiebreaker. Respects the
  /// optional scheduling window (starts_at/ends_at). Capped at [_maxPerLaunch].
  Future<List<Map<String, dynamic>>> getEligiblePopups() async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final response = await SupabaseConfig.client
          .from('admin_popups')
          .select()
          .eq('is_active', true)
          // Scheduling window: a null bound means "no bound on that side".
          .or('starts_at.is.null,starts_at.lte.$nowIso')
          .or('ends_at.is.null,ends_at.gte.$nowIso')
          .order('priority', ascending: false)
          .order('created_at', ascending: false);

      final popups = (response as List<dynamic>).cast<Map<String, dynamic>>();
      if (popups.isEmpty) return const [];

      final prefs = await SharedPreferences.getInstance();

      final eligible = <Map<String, dynamic>>[];
      for (final popup in popups) {
        if (_isEligible(popup, prefs)) {
          eligible.add(popup);
          if (eligible.length >= _maxPerLaunch) break;
        }
      }
      return eligible;
    } catch (e) {
      print('❌ Error fetching admin popups: $e');
      return const [];
    }
  }

  /// A popup is eligible if it's never been seen, or its cooldown has elapsed.
  /// cooldown_days null/<=0 means "show once, never again".
  bool _isEligible(Map<String, dynamic> popup, SharedPreferences prefs) {
    final popupId = popup['id'] as String;
    final lastSeenIso = prefs.getString('$_seenPrefix$popupId');
    if (lastSeenIso == null) return true; // never seen

    final cooldownDays = popup['cooldown_days'] as int?;
    if (cooldownDays == null || cooldownDays <= 0) return false; // once only

    final lastSeen = DateTime.tryParse(lastSeenIso);
    if (lastSeen == null) return true; // corrupt timestamp → treat as unseen
    return DateTime.now().difference(lastSeen).inDays >= cooldownDays;
  }

  /// Called when the user dismisses the popup. Saves the timestamp.
  Future<void> markPopupAsSeen(String popupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_seenPrefix$popupId',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('❌ Error marking popup as seen: $e');
    }
  }

  /// Records that a popup was shown. Fire-and-forget — analytics must never
  /// throw into the launch path. The RPC no-ops on an unknown kind / missing id.
  Future<void> recordImpression(String popupId) =>
      _recordStat(popupId, 'impression');

  /// Records that the user tapped the popup's action. Fire-and-forget.
  Future<void> recordTap(String popupId) => _recordStat(popupId, 'tap');

  Future<void> _recordStat(String popupId, String kind) async {
    try {
      await SupabaseConfig.client.rpc(
        'increment_popup_stat',
        params: {'p_popup_id': popupId, 'p_kind': kind},
      );
    } catch (e) {
      print('⚠️ Popup $kind stat failed (non-fatal): $e');
    }
  }
}
