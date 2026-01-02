import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Optimized: Fetches matches using O(1) RPC
  Future<List<Map<String, dynamic>>> getTripMatches(String tripId) async {
    try {
      final response = await _client.rpc(
        'get_trip_matches',
        params: {'target_trip_id': tripId},
      );
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching trip matches: $e');
      return [];
    }
  }

  // Optimized: Joins/Creates a Monthly Bucket Chat
  Future<Map<String, dynamic>?> joinTripGroupChat(String tripId) async {
    try {
      // 1. Get trip details to calculate bucket
      final trip = await _client
          .from('user_trips')
          .select()
          .eq('id', tripId)
          .single();

      final city = trip['destination_city'].toString().toUpperCase().replaceAll(
        RegExp(r'[^A-Z]'),
        '',
      );
      final country = trip['destination_country']
          .toString()
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z]'), '');
      final startDate = DateTime.parse(trip['start_date']);

      // BUCKET STRATEGY: City_Country_YYYY_MM
      // e.g., TOKYO_JAPAN_2026_01
      final bucketId =
          '${city}_${country}_${startDate.year}_${startDate.month.toString().padLeft(2, '0')}';

      // 2. Ensure Chat Exists (Idempotent)
      // We try to insert, if conflict (already exists), we select it
      // Note: trip_group_chats constraint is (destination_city, destination_country, start_date, end_date)
      // We will adjust the schema reuse or just store the bucket ID as the channel

      // Let's use the 'ably_channel_id' as the unique key for the bucket
      // We'll create a chat entry representing this month
      // start/end dates for the CHAT will be the full month

      final monthStart = DateTime(startDate.year, startDate.month, 1);
      final monthEnd = DateTime(
        startDate.year,
        startDate.month + 1,
        0,
      ); // Last day of month

      Map<String, dynamic>? chat;

      // Try to find existing chat for this bucket
      final existingChats = await _client
          .from('trip_group_chats')
          .select()
          .eq('ably_channel_id', bucketId)
          .limit(1);

      if (existingChats.isNotEmpty) {
        chat = existingChats.first;
      } else {
        // Create new monthly chat
        try {
          chat = await _client
              .from('trip_group_chats')
              .insert({
                'destination_city': trip['destination_city'],
                'destination_country': trip['destination_country'],
                'start_date': monthStart.toIso8601String(),
                'end_date': monthEnd.toIso8601String(),
                'ably_channel_id': bucketId,
              })
              .select()
              .single();
        } catch (e) {
          // Race condition handling: check again
          chat = await _client
              .from('trip_group_chats')
              .select()
              .eq('ably_channel_id', bucketId)
              .single();
        }
      }

      // 3. Add User to Chat Participants
      final user = _client.auth.currentUser;
      if (user != null) {
        await _client.from('trip_chat_participants').upsert({
          'chat_id': chat['id'],
          'user_id': user.id,
          'last_read_at': DateTime.now().toIso8601String(),
        }, onConflict: 'chat_id, user_id');
      }

      return {'channelId': bucketId, 'chatId': chat['id']};
    } catch (e) {
      print('❌ Error joining trip chat: $e');
      return null;
    }
  }

  // Delete a trip
  Future<bool> deleteTrip(String tripId) async {
    try {
      await _client.from('user_trips').delete().eq('id', tripId);
      return true;
    } catch (e) {
      print('❌ Error deleting trip: $e');
      return false;
    }
  }
}
