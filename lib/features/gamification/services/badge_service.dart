import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/badge.dart';
import 'package:bitemates/features/gamification/models/gamification_stats.dart';
import 'package:bitemates/features/gamification/models/user_badge.dart';

/// XP awarded per action
class XpValues {
  static const int hostEvent = 100;
  static const int joinEvent = 50;
  static const int checkIn = 75;
  static const int makeConnection = 25;
}

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
        .select('*, badges(*)')
        .eq('user_id', userId);
    return (response as List).map((e) => UserBadge.fromJson(e)).toList();
  }

  /// Fetch user's current stats (includes totalXp and level)
  Future<GamificationStats?> getUserStats(String userId) async {
    final response = await _supabase
        .from('user_gamification_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (response == null) return null;
    return GamificationStats.fromJson(response);
  }

  /// Award raw XP via the DB function. Returns updated xp and level.
  Future<({int xp, int level, bool leveledUp})> awardXp(
    String userId,
    int xp,
  ) async {
    final result = await _supabase.rpc(
      'award_xp',
      params: {'p_user_id': userId, 'p_xp': xp},
    );
    final row = (result as List).first as Map<String, dynamic>;
    return (
      xp: row['new_total_xp'] as int,
      level: row['new_level'] as int,
      leveledUp: row['leveled_up'] as bool,
    );
  }

  /// Increment user stats, award XP, and check for new badge awards.
  /// [baseXp] is the XP for the action itself (use XpValues constants).
  /// Returns list of newly awarded badges (for celebration UI).
  Future<List<Badge>> incrementStats(
    String userId, {
    int hosted = 0,
    int attended = 0,
    int connections = 0,
    int checkins = 0,
    int qrVerified = 0,
    int? uniquePeople,
    int? uniqueLocations,
    bool isVerified = false,
    int baseXp = 0,
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
        'total_xp': 0,
        'level': 1,
      };
    } else {
      data = Map<String, dynamic>.from(res);
    }

    // 2. Increment counters
    data['total_events_hosted'] = (data['total_events_hosted'] as int) + hosted;
    data['total_events_attended'] =
        (data['total_events_attended'] as int) + attended;
    data['total_connections_made'] =
        (data['total_connections_made'] as int) + connections;
    data['total_checkins'] = (data['total_checkins'] as int? ?? 0) + checkins;
    data['total_qr_verified'] =
        (data['total_qr_verified'] as int? ?? 0) + qrVerified;
    if (uniquePeople != null) data['unique_people_met'] = uniquePeople;
    if (uniqueLocations != null) data['unique_locations'] = uniqueLocations;
    data['updated_at'] = DateTime.now().toIso8601String();

    // 3. Upsert stats (without XP — that goes through award_xp to keep it atomic)
    await _supabase.from('user_gamification_stats').upsert(data);

    // 4. Award base XP via DB function
    final List<Badge> newlyAwarded = [];
    int totalXpToAward = baseXp;

    // 5. Check for newly earned badges
    try {
      final stats = GamificationStats.fromJson(data);
      final allBadges = await getAllBadges();
      final earnedBadges = await getUserBadges(userId);
      final earnedIds = earnedBadges.map((e) => e.badgeId).toSet();

      for (final badge in allBadges) {
        if (earnedIds.contains(badge.id)) continue;
        if (_meetsRequirements(
          badge.requirements,
          stats,
          isVerified: isVerified,
        )) {
          await _awardBadge(userId, badge.id);
          newlyAwarded.add(badge);
          totalXpToAward += badge.xpReward; // stack badge XP
        }
      }
    } catch (e) {
      print('Error checking badge awards: $e');
    }

    // 6. Award all XP at once
    if (totalXpToAward > 0) {
      await awardXp(userId, totalXpToAward);
    }

    return newlyAwarded;
  }

  bool _meetsRequirements(
    Map<String, dynamic> reqs,
    GamificationStats stats, {
    bool isVerified = false,
  }) {
    if (reqs.containsKey('min_hosted')) {
      if (stats.totalEventsHosted < (reqs['min_hosted'] as int)) return false;
    }
    if (reqs.containsKey('min_attended')) {
      if (stats.totalEventsAttended < (reqs['min_attended'] as int))
        return false;
    }
    if (reqs.containsKey('min_checkins')) {
      if (stats.totalCheckins < (reqs['min_checkins'] as int)) return false;
    }
    if (reqs.containsKey('min_unique_people')) {
      if (stats.uniquePeopleMet < (reqs['min_unique_people'] as int))
        return false;
    }
    if (reqs.containsKey('min_unique_locations')) {
      if (stats.uniqueLocations < (reqs['min_unique_locations'] as int))
        return false;
    }
    if (reqs.containsKey('verified')) {
      if (!isVerified) return false;
    }
    return true;
  }

  Future<void> _awardBadge(String userId, String badgeId) async {
    try {
      await _supabase.from('user_badges').insert({
        'user_id': userId,
        'badge_id': badgeId,
      });
      print('🏆 Badge Awarded: $badgeId to $userId');

      // Create in-app notification for the badge
      try {
        final badge = (await _supabase
            .from('badges')
            .select('name, tier')
            .eq('id', badgeId)
            .single());
        await _supabase.from('notifications').insert({
          'user_id': userId,
          'type': 'badge_earned',
          'title': 'Badge Earned! 🏆',
          'body': 'You earned the ${badge['name']} (${badge['tier']}) badge!',
          'metadata': {'badge_id': badgeId, 'badge_name': badge['name']},
        });
      } catch (e) {
        print('⚠️ Failed to create badge notification: $e');
      }
    } catch (e) {
      print('Badge already awarded or error: $e');
    }
  }
}
