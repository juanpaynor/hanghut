import 'package:bitemates/core/config/supabase_config.dart';

/// Service to fetch friends (people current user follows) who joined
/// the same event, table, or experience.
class FriendsGoingService {
  final _client = SupabaseConfig.client;

  /// Friends who hold valid tickets for an event
  Future<List<Map<String, dynamic>>> getFriendsGoingToEvent(
      String eventId) async {
    try {
      final response = await _client.rpc(
        'get_friends_going_to_event',
        params: {'p_event_id': eventId},
      );
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('FriendsGoingService: Error fetching event friends: $e');
      return [];
    }
  }

  /// Friends who are active members of a table/activity
  Future<List<Map<String, dynamic>>> getFriendsAtTable(String tableId) async {
    try {
      final response = await _client.rpc(
        'get_friends_at_table',
        params: {'p_table_id': tableId},
      );
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('FriendsGoingService: Error fetching table friends: $e');
      return [];
    }
  }

  /// Friends who booked an experience
  Future<List<Map<String, dynamic>>> getFriendsInExperience(
      String tableId) async {
    try {
      final response = await _client.rpc(
        'get_friends_in_experience',
        params: {'p_table_id': tableId},
      );
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('FriendsGoingService: Error fetching experience friends: $e');
      return [];
    }
  }

  /// After joining an entity, notify friends who are already there
  Future<void> notifyFriendsOfJoin({
    required String entityType,
    required String entityId,
    required String entityTitle,
  }) async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) return;

      // Check if current user has privacy enabled
      final userRow = await _client
          .from('users')
          .select('hide_activity_from_friends, display_name')
          .eq('id', currentUser.id)
          .single();

      if (userRow['hide_activity_from_friends'] == true) return;

      final displayName = userRow['display_name'] ?? 'Someone';

      // Get friends who follow the current user (so they get notified)
      final followers = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', currentUser.id);

      if (followers.isEmpty) return;

      final followerIds =
          (followers as List).map((f) => f['follower_id'] as String).toSet();

      // Get members of the entity to intersect with followers
      List<String> memberIds = [];
      if (entityType == 'table') {
        final members = await _client
            .from('table_members')
            .select('user_id')
            .eq('table_id', entityId)
            .eq('status', 'joined');
        memberIds =
            (members as List).map((m) => m['user_id'] as String).toList();
      } else if (entityType == 'event') {
        final ticketHolders = await _client
            .from('tickets')
            .select('user_id')
            .eq('event_id', entityId)
            .eq('status', 'valid');
        memberIds = (ticketHolders as List)
            .map((t) => t['user_id'] as String)
            .toList();
      } else if (entityType == 'experience') {
        final bookers = await _client
            .from('experience_purchase_intents')
            .select('user_id')
            .eq('table_id', entityId)
            .eq('status', 'completed');
        memberIds =
            (bookers as List).map((b) => b['user_id'] as String).toList();
      }

      // Intersection: followers who are also members of this entity
      final friendsToNotify = memberIds
          .where((id) => followerIds.contains(id) && id != currentUser.id)
          .toList();

      if (friendsToNotify.isEmpty) return;

      // Batch insert notifications
      final notifications = friendsToNotify
          .map((friendId) => {
                'user_id': friendId,
                'actor_id': currentUser.id,
                'type': 'friend_joined',
                'entity_id': entityId,
                'title': '$displayName joined $entityTitle',
                'body':
                    'Your friend $displayName just joined "$entityTitle" — you\'re going too!',
                'metadata': {
                  'entity_type': entityType,
                  'entity_id': entityId,
                  'entity_title': entityTitle,
                },
              })
          .toList();

      await _client.from('notifications').insert(notifications);
    } catch (e) {
      print('FriendsGoingService: Error notifying friends: $e');
    }
  }
}
