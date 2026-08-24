import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';

/// Read access to partner-authored loyalty badges (team_comms #243/#244).
///
/// Awarding is SERVER-SIDE ONLY (SECURITY DEFINER functions); the client only
/// ever reads. `user_creator_badges` is public-SELECT with no client write path,
/// so there is deliberately nothing here that inserts/updates.
class CreatorBadgeService {
  final _supabase = SupabaseConfig.client;

  /// Badges a user has earned, newest first. Rarity comes from the joined
  /// `holder_count` (never client-aggregated, per the contract).
  Future<List<EarnedCreatorBadge>> getEarnedBadges(String userId) async {
    try {
      final response = await _supabase
          .from('user_creator_badges')
          .select('id, earned_at, grant_type, badge:creator_badges(*)')
          .eq('user_id', userId)
          .order('earned_at', ascending: false);

      return (response as List)
          .map((e) => EarnedCreatorBadge.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          // Defensive: only surface active badges with a resolvable record.
          .where((b) => b.badge.isActive)
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('❌ CreatorBadgeService.getEarnedBadges failed: $e');
      return [];
    }
  }

  /// Badges the current user has earned since the last check — used to fire the
  /// celebration overlay. Records the current set as "seen" each call.
  ///
  /// On the FIRST run for a user on this install there's no baseline, so we
  /// record silently and return nothing — otherwise every already-earned badge
  /// would flood the screen with celebrations at once. Only badges that appear
  /// AFTER the baseline (including claim-time awards after signup) celebrate.
  Future<List<CreatorBadge>> getNewlyEarnedBadges() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final earned = await getEarnedBadges(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'seen_creator_badges_$userId';
      final seen = prefs.getStringList(key);
      final currentIds = earned.map((e) => e.badge.id).toList();

      if (seen == null) {
        // First run for this user — baseline, don't celebrate the back-catalog.
        await prefs.setStringList(key, currentIds);
        return [];
      }

      final seenSet = seen.toSet();
      final fresh = earned.where((e) => !seenSet.contains(e.badge.id)).toList();
      if (fresh.isNotEmpty) {
        await prefs.setStringList(key, {...seen, ...currentIds}.toList());
      }
      return fresh.map((e) => e.badge).toList();
    } catch (_) {
      return [];
    }
  }

  /// All active badges a partner offers — for storefront "badges you can earn"
  /// surfaces. Ordered by rarity (rarest first) so standout badges lead.
  Future<List<CreatorBadge>> getPartnerBadges(String organizerId) async {
    try {
      final response = await _supabase
          .from('creator_badges')
          .select()
          .eq('organizer_id', organizerId)
          .eq('is_active', true)
          .order('holder_count', ascending: true);

      return (response as List)
          .map((e) => CreatorBadge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('❌ CreatorBadgeService.getPartnerBadges failed: $e');
      return [];
    }
  }
}
