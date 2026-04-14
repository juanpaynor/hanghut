import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/models/gamification_stats.dart';
import 'package:bitemates/features/gamification/models/user_badge.dart';

class BadgeService {
  final _supabase = SupabaseConfig.client;

  /// Fetch all available badges
  Future<List<Badge>> getAllBadges() async {
    final response = await _supabase.from('badges').select();
    return (response as List).map((e) => Badge.fromJson(e)).toList();
  }

  /// Fetch badges earned by a specific user
  Future<List<UserBadge>> getUserBadges(String userId) async {
    final response = await _supabase
        .from('user_badges')
        .select('*, badges(*)') // Join with badges table
        .eq('user_id', userId);

    return (response as List).map((e) => UserBadge.fromJson(e)).toList();
  }

  /// Fetch user's current stats
  Future<GamificationStats?> getUserStats(String userId) async {
    final response = await _supabase
        .from('user_gamification_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return GamificationStats.fromJson(response);
  }

  /// Increment user stats and check for new badge awards
  /// Returns list of newly awarded badges (for celebration UI)
  Future<List<Badge>> incrementStats(
    String userId, {
    int hosted = 0,
    int attended = 0,
    int connections = 0,
    int checkins = 0,
    int qrVerified = 0,
    int? uniquePeople,
    int? uniqueLocations,
  }) async {
    // 1. Get current stats or initialize
    final res = await _supabase
        .from('user_gamification_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    Map<String, dynamic> data;
    if (res == null) {
      data = {
        'user_id': userId,
        'total_events_hosted': 0,
        'total_events_attended': 0,
        'total_connections_made': 0,
        'total_checkins': 0,
        'total_qr_verified': 0,
        'unique_people_met': 0,
        'unique_locations': 0,
      };
    } else {
      data = Map<String, dynamic>.from(res);
    }

    // 2. Increment values
    data['total_events_hosted'] = (data['total_events_hosted'] as int) + hosted;
    data['total_events_attended'] =
        (data['total_events_attended'] as int) + attended;
    data['total_connections_made'] =
        (data['total_connections_made'] as int) + connections;
    data['total_checkins'] = (data['total_checkins'] as int? ?? 0) + checkins;
    data['total_qr_verified'] = (data['total_qr_verified'] as int? ?? 0) + qrVerified;
    // Unique counts are absolute (not increments)
    if (uniquePeople != null) data['unique_people_met'] = uniquePeople;
    if (uniqueLocations != null) data['unique_locations'] = uniqueLocations;
    data['updated_at'] = DateTime.now().toIso8601String();

    // 3. Upsert
    await _supabase.from('user_gamification_stats').upsert(data);

    // 4. Check for awards
    return await _checkAwards(userId, GamificationStats.fromJson(data));
  }

  /// Internal method to check and award badges
  /// Returns list of newly awarded badges
  Future<List<Badge>> _checkAwards(String userId, GamificationStats stats) async {
    final List<Badge> newlyAwarded = [];
    try {
      // Get all badges
      final allBadges = await getAllBadges();

      // Get already earned badges
      final earnedBadges = await getUserBadges(userId);
      final earnedids = earnedBadges.map((e) => e.badgeId).toSet();

      for (final badge in allBadges) {
        if (earnedids.contains(badge.id)) continue;

        if (_meetsRequirements(badge.requirements, stats)) {
          await _awardBadge(userId, badge.id);
          newlyAwarded.add(badge);
        }
      }
    } catch (e) {
      print('Error checking awards: $e');
    }
    return newlyAwarded;
  }

  bool _meetsRequirements(Map<String, dynamic> reqs, GamificationStats stats) {
    if (reqs.containsKey('min_hosted')) {
      final minHosted = reqs['min_hosted'] as int;
      if (stats.totalEventsHosted < minHosted) return false;
    }

    if (reqs.containsKey('min_attended')) {
      final minAttended = reqs['min_attended'] as int;
      if (stats.totalEventsAttended < minAttended) return false;
    }

    if (reqs.containsKey('min_checkins')) {
      final minCheckins = reqs['min_checkins'] as int;
      if (stats.totalCheckins < minCheckins) return false;
    }

    if (reqs.containsKey('min_unique_people')) {
      final minPeople = reqs['min_unique_people'] as int;
      if (stats.uniquePeopleMet < minPeople) return false;
    }

    if (reqs.containsKey('min_unique_locations')) {
      final minLocations = reqs['min_unique_locations'] as int;
      if (stats.uniqueLocations < minLocations) return false;
    }

    return true;
  }

  Future<void> _awardBadge(String userId, String badgeId) async {
    try {
      await _supabase.from('user_badges').insert({
        'user_id': userId,
        'badge_id': badgeId,
      });
      // In a real app, we might trigger a local notification here
      print('🏆 Badge Awarded: $badgeId to $userId');
    } catch (e) {
      // Handles unique constraint violation if race condition occurs
      print('Badge already awarded or error: $e');
    }
  }
}
