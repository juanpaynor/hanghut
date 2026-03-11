import 'package:bitemates/core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminPopupService {
  static const String _seenPrefix = 'popup_seen_';

  /// Fetches all active popups from Supabase and returns the first one
  /// that the user is eligible to see (not in cooldown).
  Future<Map<String, dynamic>?> checkAndGetActivePopup() async {
    try {
      // 1. Fetch ALL active popups from Supabase, newest first
      final response = await SupabaseConfig.client
          .from('admin_popups')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final popups = response as List<dynamic>;

      if (popups.isEmpty) {
        return null; // No active popups at all
      }

      final prefs = await SharedPreferences.getInstance();

      // 2. Iterate through them to find the first one the user should see
      for (final popup in popups) {
        final popupData = popup as Map<String, dynamic>;
        final popupId = popupData['id'] as String;
        final cooldownDays = popupData['cooldown_days'] as int?;

        final lastSeenIso = prefs.getString('$_seenPrefix$popupId');

        if (lastSeenIso == null) {
          // Never seen this one! Show it.
          return popupData;
        }

        final lastSeenDate = DateTime.parse(lastSeenIso);

        // Option A: Never show again
        if (cooldownDays == null || cooldownDays <= 0) {
          continue; // Move to the next popup in the list
        }

        // Option B: Check if cooldown period is over
        final timePassed = DateTime.now().difference(lastSeenDate);
        if (timePassed.inDays >= cooldownDays) {
          return popupData; // Cooldown is over, show it!
        }
      }

      // If we made it here, all active popups are either dismissed permanently
      // or currently on cooldown. Show nothing.
      return null;
    } catch (e) {
      print('❌ Error fetching admin popup: $e');
      return null;
    }
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
}
