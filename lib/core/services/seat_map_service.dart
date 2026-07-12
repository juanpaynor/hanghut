import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/models/seat_map.dart';

/// Customer-facing seat map data layer (team_comms #166 contract).
class SeatMapService {
  /// Fetches the seat map for an event. Returns null when the event has no map
  /// (caller falls back to normal quantity checkout).
  Future<SeatMap?> getEventSeatMap(String eventId) async {
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_event_seat_map',
        params: {'p_event_id': eventId},
      );
      if (result == null) return null;
      if (result is Map) {
        return SeatMap.fromJson(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (e) {
      print('⚠️ getEventSeatMap failed: $e');
      return null;
    }
  }

  /// Subscribes to live seat status changes for an event. Fires for
  /// booked/released/disabled transitions. NOTE: holds are NOT reflected in
  /// seats.status (overlaid from seat_holds, which has no event_id) — rely on a
  /// periodic refetch for others' holds; checkout SEATS_UNAVAILABLE is the final
  /// source of truth.
  ///
  /// [onSeatUpdate] receives the new seat id + status. Returns the channel so
  /// the caller can `removeChannel` on dispose.
  RealtimeChannel subscribeSeatUpdates(
    String eventId,
    void Function(String seatId, String status) onSeatUpdate,
  ) {
    final channel = SupabaseConfig.client
        .channel('seat_map:$eventId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'seats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            final id = rec['id']?.toString();
            final status = rec['status']?.toString();
            if (id != null && status != null) onSeatUpdate(id, status);
          },
        )
        .subscribe();
    return channel;
  }

  void unsubscribe(RealtimeChannel channel) {
    SupabaseConfig.client.removeChannel(channel);
  }
}
