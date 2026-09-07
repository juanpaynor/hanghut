import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/gamification/models/creator_badge.dart';

/// Session-lifetime cache of badge metadata, so a pinned stamp can appear beside
/// every name in a feed without costing a query per row.
///
/// The split that makes inline badges affordable: the *pointer* to a user's
/// pinned badge (`users.featured_creator_badge_ids`) rides along in the user
/// embeds the feed already selects, while the badge's own art/tier/holder_count
/// is fetched here — once, in one batched query, for the handful of distinct
/// badges actually on screen. A feed shows posts from many people but badges
/// from few partners, so the set stays small and reuse is near-total.
///
/// Badge rows change rarely (art, tier, holder_count), so a session memo is the
/// right granularity. Misses are remembered too — an id that resolves to nothing
/// (deleted, or filtered out as inactive) must not re-query on every rebuild.
class CreatorBadgeCache {
  CreatorBadgeCache._();
  static final CreatorBadgeCache instance = CreatorBadgeCache._();

  final _supabase = SupabaseConfig.client;

  final Map<String, CreatorBadge> _byId = {};
  final Set<String> _known404 = {};
  final Set<String> _inFlight = {};

  /// Synchronous read for build methods — null when not yet loaded OR known
  /// absent. Callers render nothing rather than a placeholder, so a stamp fades
  /// in once resolved instead of reserving space it may never use.
  CreatorBadge? peek(String badgeId) => _byId[badgeId];

  /// True once we've settled this id either way, so a widget can stop retrying.
  bool isResolved(String badgeId) =>
      _byId.containsKey(badgeId) || _known404.contains(badgeId);

  /// Resolve one badge, fetching only if it isn't already settled.
  Future<CreatorBadge?> resolve(String badgeId) async {
    if (isResolved(badgeId)) return _byId[badgeId];
    await prime([badgeId]);
    return _byId[badgeId];
  }

  /// Fetch every id in [badgeIds] that isn't already settled or in flight — in a
  /// single query. Safe to call on every list build; it no-ops once warm.
  Future<void> prime(Iterable<String> badgeIds) async {
    final want = badgeIds
        .where((id) =>
            id.isNotEmpty &&
            !_byId.containsKey(id) &&
            !_known404.contains(id) &&
            !_inFlight.contains(id))
        .toSet();
    if (want.isEmpty) return;

    _inFlight.addAll(want);
    try {
      final rows = await _supabase
          .from('creator_badges')
          .select('*')
          .inFilter('id', want.toList());

      for (final row in (rows as List)) {
        final badge =
            CreatorBadge.fromJson(Map<String, dynamic>.from(row as Map));
        // Inactive badges are cached as absent: an earned badge is permanent,
        // but a deactivated one shouldn't keep advertising a partner inline.
        if (badge.isActive) {
          _byId[badge.id] = badge;
        } else {
          _known404.add(badge.id);
        }
      }

      for (final id in want) {
        if (!_byId.containsKey(id)) _known404.add(id);
      }
    } catch (e) {
      // Leave the ids unsettled so a later build can retry — a transient network
      // failure shouldn't permanently blank someone's stamp for the session.
      // ignore: avoid_print
      print('❌ CreatorBadgeCache.prime failed: $e');
    } finally {
      _inFlight.removeAll(want);
    }
  }

  /// Pull the pinned badge id out of a user payload that carries
  /// `featured_creator_badge_ids`. Position 0 is the pin: web stores the array
  /// as given and we treat position as display order (team_comms #297).
  static String? pinnedIdFrom(Map<String, dynamic>? user) {
    final raw = user?['featured_creator_badge_ids'];
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is String && first.isNotEmpty) return first;
    }
    return null;
  }

  /// Test/debug only — drops everything so the next read refetches.
  void clear() {
    _byId.clear();
    _known404.clear();
    _inFlight.clear();
  }
}
