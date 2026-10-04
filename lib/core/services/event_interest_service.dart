import 'package:flutter/foundation.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/models/event_social_proof.dart';

/// Reads and writes "I'm interested" on events.
///
/// The mirror of the social-proof methods on [TableMemberService], kept
/// separate because interest in an event is a row in its own table
/// (`event_interests`) rather than a membership status.
///
/// Note on the analytics table: interest deliberately does NOT go into
/// `event_interactions`. That type vocabulary is a contract with web's
/// organizer analytics — view · get_tickets · pick_seats · checkout_started ·
/// share — and adding a sixth value would change numbers on their dashboard
/// (team_comms #240, reaffirmed in #340).
class EventInterestService {
  EventInterestService._();
  static final EventInterestService instance = EventInterestService._();

  /// Social proof for a page of events, in ONE round trip.
  ///
  /// Always batch. A per-card fetch would mean 20 requests to draw one
  /// screen of Discover, which is the N+1 the feed already avoids by loading
  /// hangout proof per page (feed_screen._loadHangoutProof).
  ///
  /// Returns a map keyed by event id. Missing ids simply mean "nothing known",
  /// so a caller renders [EventSocialProof.unknown] rather than failing — which
  /// is also what happens before the RPC is deployed.
  Future<Map<String, EventSocialProof>> getSocialProofFor(
    List<String> eventIds,
  ) async {
    final ids = eventIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final res = await SupabaseConfig.client
          .rpc('get_event_social_proof', params: {'p_event_ids': ids});
      if (res is! Map) return {};
      final out = <String, EventSocialProof>{};
      res.forEach((key, value) {
        if (value is Map) {
          out[key.toString()] =
              EventSocialProof.fromJson(Map<String, dynamic>.from(value));
        }
      });
      return out;
    } catch (e) {
      // Social proof is decoration on top of an event that still works without
      // it. A failure here must never take out the list it was garnishing.
      if (kDebugMode) debugPrint('⚠️ get_event_social_proof failed: $e');
      return {};
    }
  }

  /// Proof for a single event. Convenience only — prefer the batched call.
  Future<EventSocialProof> getSocialProof(String eventId) async {
    final map = await getSocialProofFor([eventId]);
    return map[eventId] ?? EventSocialProof.unknown;
  }

  /// Register interest. Idempotent: tapping twice is not an error.
  Future<bool> markInterested(String eventId) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null || eventId.isEmpty) return false;
    try {
      await SupabaseConfig.client.from('event_interests').upsert(
        {'event_id': eventId, 'user_id': userId},
        onConflict: 'event_id,user_id',
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ markInterested failed: $e');
      return false;
    }
  }

  Future<bool> removeInterest(String eventId) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null || eventId.isEmpty) return false;
    try {
      await SupabaseConfig.client
          .from('event_interests')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ removeInterest failed: $e');
      return false;
    }
  }
}
