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

  /// Lightweight reconciling poll (team_comms #284: "keep a reconciling poll as
  /// the floor"). Returns only what changes at runtime — seats that are NOT
  /// available (holds folded in) plus per-section remaining availability — so it
  /// is cheap enough to run every few seconds behind the Ably fast path.
  /// Returns null when the event has no seat map.
  Future<SeatStatusSnapshot?> getEventSeatStatus(String eventId) async {
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_event_seat_status',
        params: {'p_event_id': eventId},
      );
      if (result is Map) {
        return SeatStatusSnapshot.fromJson(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (e) {
      print('⚠️ getEventSeatStatus failed: $e');
      return null;
    }
  }

  // Live seat updates now run over Ably per section (see SeatRealtimeService,
  // team_comms #284/#287) — postgres_changes could never see others' holds
  // (seat_holds has no event_id), so the old subscribeSeatUpdates was removed in
  // favour of the Ably fast path + getEventSeatStatus reconciling poll.
}
