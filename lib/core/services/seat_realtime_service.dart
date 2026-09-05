import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:http/http.dart' as http;
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// Result of POST /api/seat-map/hold (team_comms #291). [seatsHeld] is a COUNT,
/// read after the write in the same request. [reason] is additive: web populates
/// it ('taken' | 'unavailable' | 'limit') only on the held:false path and only
/// once asked for — absent otherwise, so never assume the key exists.
class SeatHoldResult {
  final bool held;
  final DateTime? expiresAt;
  final DateTime? serverNow;
  final int seatsHeld;
  final String? reason;

  const SeatHoldResult({
    required this.held,
    this.expiresAt,
    this.serverNow,
    this.seatsHeld = 0,
    this.reason,
  });

  /// A held:false result standing in for a failed request (network/500) so the
  /// caller reverts the optimistic selection instead of leaving a phantom hold.
  static const failed = SeatHoldResult(held: false);
}

/// Per-section seat-map live updates over Ably PLUS the hold/release lifecycle
/// (team_comms #284 / #287 / #289 / #291).
///
/// Contract (web-owned — do NOT diverge):
///   channel : hh:{scope}:seatmap:{eventId}:{sectionId}
///             scope = Supabase project ref from the URL host (`api` on prod).
///   message : name = 'held' | 'released' | 'booked',
///             data = { seatId, origin? }  (origin OMITTED, not null, when the
///             publisher sent none — treat absent as "not mine")
///   subscribe auth : subscribe-only token from GET /api/seat-map/realtime-token,
///                    via authCallback (1h TTL — the SDK auto-refreshes).
///   hold    : POST /api/seat-map/hold { seatId, sessionId, origin } — ONE seat
///             per call, NO auth (guests hold fine), 12-min TTL.
///   release : POST /api/seat-map/release { sessionId, seatIds[], origin } —
///             partial ok, cap 50 ids.
///
/// ADVISORY ONLY. Messages may drop, duplicate, or arrive late/out of order;
/// Postgres stays the sole authority (UNIQUE(seat_id) on hold, FOR UPDATE SKIP
/// LOCKED on assign, checkout SEATS_UNAVAILABLE/SEATS_EXPIRED is final truth). A
/// reconciling poll (SeatMapService.getEventSeatStatus) remains the floor.
///
/// Echo discard: hold/release publish back to the section channel we subscribe
/// to, so a message whose `origin` equals ours is our OWN action — dropped, so
/// the poll/UI never grey out the buyer's own seats. Discard is by origin, NEVER
/// by "is this seat in my selection" (that races on a fast unpick — #289).
class SeatRealtimeService {
  SeatRealtimeService({
    required this.eventId,
    required this.sessionId,
    required this.origin,
    required this.onSeatUpdate,
  });

  final String eventId;

  /// Credential for hold/release AND the value sent as `seat_session_id` at
  /// checkout so assign_seats_to_intent recognises our own holds (#291 Trap 1).
  final String sessionId;

  /// Random per-picker tag echoed back in the broadcast so we can drop our own
  /// messages. Deliberately NOT the sessionId — the sessionId is a credential
  /// and is never broadcast.
  final String origin;

  /// Fires when a seat changes. [status] is one of
  /// 'available' (released) | 'held' | 'booked'. Never fires for our own echo.
  final void Function(String seatId, String status) onSeatUpdate;

  ably.Realtime? _realtime;
  StreamSubscription<ably.Message>? _sub;
  String? _sectionId;

  /// Project ref from the Supabase URL host — `api` on api.hanghut.com. Keyed on
  /// the DB (not NODE_ENV) so different databases can never cross-talk (#284).
  static String get _scope =>
      Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first;

  String _channelName(String sectionId) =>
      'hh:$_scope:seatmap:$eventId:$sectionId';

  /// Fetches a subscribe-only Ably token for this event from web.
  Future<Object> _authCallback(ably.TokenParams params) async {
    final uri = Uri.parse(
      '${AppConstants.webBaseUrl}/api/seat-map/realtime-token?eventId=$eventId',
    );
    final session = SupabaseConfig.auth.currentSession;
    final res = await http.get(uri, headers: {
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    });
    if (res.statusCode != 200) {
      throw Exception('realtime-token ${res.statusCode}: ${res.body}');
    }
    final token = (jsonDecode(res.body) as Map)['token'] as String;
    return ably.TokenDetails(token);
  }

  /// Opens the Ably connection (authenticates once) without subscribing to any
  /// channel yet. Idempotent. Failures are swallowed: realtime is a latency
  /// optimisation and must never break the picker.
  void start() {
    if (_realtime != null) return;
    try {
      _realtime = ably.Realtime(
        options: ably.ClientOptions(
          authCallback: _authCallback,
          autoConnect: true,
          // No `key`: the subscribe-only token is the ONLY credential this
          // client holds, so it cannot publish even by mistake.
        ),
      );
    } catch (e) {
      print('⚠️ SeatRealtime start failed: $e');
    }
  }

  /// Subscribes to exactly ONE section's channel — the one the buyer is looking
  /// at — detaching the previous one. Web meters DELIVERIES, and buyers only
  /// ever view one section at a time, so subscribing to every section would
  /// fan a single hold out to the whole event (14x on the PICC map) for a
  /// sold-out counter that only the 3s poll's sections[] can carry anyway
  /// (team_comms #289). Pass null when leaving the seat view (level-1 overview);
  /// section availability there stays fresh via the poll. Seated sections only —
  /// GA zones have no individual seats and publish nothing.
  Future<void> setSection(String? sectionId) async {
    if (sectionId == _sectionId) return;
    await _sub?.cancel();
    _sub = null;
    final prev = _sectionId;
    _sectionId = sectionId;
    final rt = _realtime;
    if (rt == null) return;
    try {
      if (prev != null) {
        await rt.channels.get(_channelName(prev)).detach();
      }
      if (sectionId != null) {
        _sub = rt.channels.get(_channelName(sectionId)).subscribe().listen(
              _onMessage,
            );
      }
    } catch (e) {
      print('⚠️ SeatRealtime setSection failed: $e');
    }
  }

  void _onMessage(ably.Message msg) {
    final status = switch (msg.name) {
      'held' => 'held',
      'released' => 'available',
      'booked' => 'booked',
      _ => null,
    };
    if (status == null) return;
    final data = _asMap(msg.data);
    // Echo discard: our own hold/release comes back on this same channel. origin
    // is OMITTED when absent, so a present-and-equal origin means it is ours.
    if (data != null && data['origin'] == origin) return;
    final seatId = data?['seatId']?.toString();
    if (seatId != null) onSeatUpdate(seatId, status);
  }

  /// Payload is `{ seatId, origin? }`. ably_flutter usually decodes JSON to a
  /// Map, but tolerate a raw JSON string too.
  Map? _asMap(Object? data) {
    if (data is Map) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Holds ONE seat server-side (creates the seat_holds row + broadcasts 'held').
  /// No auth needed. Returns held:false — with an optional [reason] — when the
  /// seat is taken, unavailable, or the session hit its per-order limit. Any
  /// network/HTTP failure returns [SeatHoldResult.failed] so the caller reverts.
  Future<SeatHoldResult> hold(String seatId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.webBaseUrl}/api/seat-map/hold'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'seatId': seatId,
          'sessionId': sessionId,
          'origin': origin,
        }),
      );
      if (res.statusCode != 200) return SeatHoldResult.failed;
      final j = jsonDecode(res.body) as Map;
      return SeatHoldResult(
        held: j['held'] == true,
        expiresAt: _parseTime(j['expiresAt']),
        serverNow: _parseTime(j['serverNow']),
        seatsHeld: (j['seatsHeld'] as num?)?.toInt() ?? 0,
        reason: j['reason']?.toString(),
      );
    } catch (e) {
      print('⚠️ SeatRealtime hold failed: $e');
      return SeatHoldResult.failed;
    }
  }

  /// Releases holds this session owns (deletes the rows + broadcasts 'released'
  /// per genuinely-freed seat). Best-effort — a failure here just leaves the hold
  /// to lapse on its 12-min TTL. Cap is 50 ids per call; we chunk to respect it.
  Future<void> release(List<String> seatIds) async {
    if (seatIds.isEmpty) return;
    for (var i = 0; i < seatIds.length; i += 50) {
      final chunk = seatIds.sublist(i, math.min(i + 50, seatIds.length));
      try {
        await http.post(
          Uri.parse('${AppConstants.webBaseUrl}/api/seat-map/release'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sessionId': sessionId,
            'seatIds': chunk,
            'origin': origin,
          }),
        );
      } catch (e) {
        print('⚠️ SeatRealtime release failed: $e');
      }
    }
  }

  DateTime? _parseTime(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _realtime?.close();
    } catch (_) {}
    _realtime = null;
  }
}
