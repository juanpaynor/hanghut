import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central check-in service handling geo and QR check-ins,
/// gamification stat updates, and badge triggers.
class CheckinService {
  static final CheckinService _instance = CheckinService._internal();
  factory CheckinService() => _instance;
  CheckinService._internal();

  final _supabase = SupabaseConfig.client;
  final _badgeService = BadgeService();

  /// Passive geo check-in — called by GeofenceEngine when near a joined activity.
  /// Returns the RPC result including success/error/distance.
  Future<Map<String, dynamic>> geoCheckin(
    String tableId,
    double lat,
    double lng,
  ) async {
    try {
      final response = await _supabase.rpc(
        'geo_checkin',
        params: {'p_table_id': tableId, 'p_user_lat': lat, 'p_user_lng': lng},
      );

      final result = Map<String, dynamic>.from(response as Map);

      // If successfully checked in (not already), update meetup stats
      if (result['success'] == true && result['already'] != true) {
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          await updateMeetupStats(userId, tableId);
        }
      }

      return result;
    } catch (e) {
      print('❌ CheckinService.geoCheckin error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get check-in status for current user in an activity
  Future<Map<String, dynamic>?> getCheckinStatus(String tableId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final result = await _supabase
          .from('activity_checkins')
          .select()
          .eq('table_id', tableId)
          .eq('user_id', userId)
          .maybeSingle();

      return result;
    } catch (e) {
      print('❌ CheckinService.getCheckinStatus error: $e');
      return null;
    }
  }

  /// Get all check-ins for an activity (for host dashboard / checkin banner)
  Future<List<Map<String, dynamic>>> getActivityCheckins(String tableId) async {
    try {
      final result = await _supabase
          .from('activity_checkins')
          .select('*, users!activity_checkins_user_id_fkey(id, display_name)')
          .eq('table_id', tableId)
          .order('checked_in_at', ascending: true);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('❌ CheckinService.getActivityCheckins error: $e');
      return [];
    }
  }

  /// Compute unique_people_met and unique_locations after a check-in
  Future<void> updateMeetupStats(String userId, String tableId) async {
    try {
      // 1. Count unique people met across all check-ins
      // (users who checked into the same activities as this user, minus self)
      final uniquePeopleResult = await _supabase.rpc(
        'get_unique_people_met',
        params: {'p_user_id': userId},
      );

      // 2. Count unique locations (distinct table locations checked into)
      final uniqueLocationsResult = await _supabase.rpc(
        'get_unique_checkin_locations',
        params: {'p_user_id': userId},
      );

      final uniquePeople = (uniquePeopleResult as int?) ?? 0;
      final uniqueLocations = (uniqueLocationsResult as int?) ?? 0;

      // 3. Update stats via BadgeService (which also checks for new badges)
      await _badgeService.incrementStats(
        userId,
        checkins: 1,
        uniquePeople: uniquePeople,
        uniqueLocations: uniqueLocations,
        baseXp: XpValues.checkIn,
      );
    } catch (e) {
      // Non-critical — stats update can fail silently
      print('⚠️ CheckinService.updateMeetupStats: $e');
    }
  }

  /// Check and award badges, returning newly earned badges for celebration UI
  Future<List<Badge>> checkAndAwardBadges(String userId) async {
    try {
      return await _badgeService.incrementStats(userId);
    } catch (e) {
      print('❌ CheckinService.checkAndAwardBadges: $e');
      return [];
    }
  }
}
