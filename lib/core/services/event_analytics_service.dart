import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// Logs event interactions to `event_interactions` with `source='app'` so web's
/// organizer analytics can tell app traffic from web (team_comms #240).
///
/// Everything here is fire-and-forget and never throws — analytics must never
/// interrupt or break a user flow (especially checkout).
class EventAnalyticsService {
  EventAnalyticsService._();
  static final EventAnalyticsService instance = EventAnalyticsService._();

  /// Stable per-install anonymous id, persisted so unique-view counts are
  /// comparable with web (which dedupes once per browser session per event).
  static const _sessionKey = 'analytics_session_id';
  String? _sessionId;

  /// Events already given a `view` this app run — dedupe like web does
  /// (at most one view per event per session).
  final Set<String> _viewedThisSession = {};

  Future<String> _getSessionId() async {
    if (_sessionId != null) return _sessionId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_sessionKey);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_sessionKey, id);
      }
      return _sessionId = id;
    } catch (_) {
      // Persistence unavailable — fall back to an ephemeral id so logging still
      // works this session rather than dropping events entirely.
      return _sessionId ??= const Uuid().v4();
    }
  }

  /// Records one interaction. Type strings MUST match web's analytics vocabulary
  /// exactly: view · get_tickets · pick_seats · checkout_started · share.
  Future<void> log(String eventId, String type) async {
    try {
      if (eventId.isEmpty) return;
      if (type == 'view') {
        if (_viewedThisSession.contains(eventId)) return;
        _viewedThisSession.add(eventId);
      }
      final sessionId = await _getSessionId();
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      await SupabaseConfig.client.from('event_interactions').insert({
        'event_id': eventId,
        'user_id': userId,
        'session_id': sessionId,
        'type': type,
        'source': 'app',
        'channel': 'app',
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ event_interactions log failed ($type): $e');
      }
    }
  }

  // Convenience wrappers for the wired touch-points.
  Future<void> logView(String eventId) => log(eventId, 'view');
  Future<void> logGetTickets(String eventId) => log(eventId, 'get_tickets');
  Future<void> logPickSeats(String eventId) => log(eventId, 'pick_seats');
  Future<void> logCheckoutStarted(String eventId) =>
      log(eventId, 'checkout_started');
  Future<void> logShare(String eventId) => log(eventId, 'share');
}
