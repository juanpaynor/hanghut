import 'package:bitemates/core/config/supabase_config.dart';

/// A scheduled club run (row of `club_runs`) with its RSVP rollup.
class ClubRun {
  final String id;
  final String groupId;
  final String? routeId;
  final String title;
  final DateTime startAt; // local
  final double? distanceM;
  final String? paceNote;
  final double? meetupLat;
  final double? meetupLng;
  final String? meetupLabel;
  final String status;
  final int goingCount;
  final bool iAmGoing;

  const ClubRun({
    required this.id,
    required this.groupId,
    required this.title,
    required this.startAt,
    this.routeId,
    this.distanceM,
    this.paceNote,
    this.meetupLat,
    this.meetupLng,
    this.meetupLabel,
    this.status = 'scheduled',
    this.goingCount = 0,
    this.iAmGoing = false,
  });

  factory ClubRun.fromJson(Map<String, dynamic> j, String? myUid) {
    final rsvps = (j['club_run_rsvps'] as List?) ?? const [];
    final going = rsvps.where((r) => (r as Map)['status'] == 'going').toList();
    return ClubRun(
      id: j['id'] as String,
      groupId: j['group_id'] as String,
      routeId: j['route_id'] as String?,
      title: (j['title'] as String?) ?? 'Club Run',
      startAt:
          DateTime.parse(j['start_at'].toString()).toLocal(),
      distanceM: (j['distance_m'] as num?)?.toDouble(),
      paceNote: j['pace_note'] as String?,
      meetupLat: (j['meetup_lat'] as num?)?.toDouble(),
      meetupLng: (j['meetup_lng'] as num?)?.toDouble(),
      meetupLabel: j['meetup_label'] as String?,
      status: (j['status'] as String?) ?? 'scheduled',
      goingCount: going.length,
      iAmGoing:
          myUid != null && going.any((r) => (r as Map)['user_id'] == myUid),
    );
  }
}

/// Data layer for scheduled club runs + RSVPs. RLS enforced server-side
/// (team_comms #281).
class ClubRunService {
  static const String _sel = '*, club_run_rsvps(user_id, status)';

  /// Upcoming (and still-relevant) runs for a club, soonest first.
  Future<List<ClubRun>> listUpcoming(String groupId) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    try {
      // Keep a run visible until ~6h after start (mid-run / just-finished).
      final from = DateTime.now()
          .subtract(const Duration(hours: 6))
          .toUtc()
          .toIso8601String();
      final rows = await SupabaseConfig.client
          .from('club_runs')
          .select(_sel)
          .eq('group_id', groupId)
          .eq('status', 'scheduled')
          .gte('start_at', from)
          .order('start_at', ascending: true);
      return (rows as List)
          .map((r) => ClubRun.fromJson(Map<String, dynamic>.from(r), uid))
          .toList();
    } catch (e) {
      print('⚠️ listUpcoming failed: $e');
      return [];
    }
  }

  Future<ClubRun?> createRun({
    required String groupId,
    required String title,
    required DateTime startAt,
    String? routeId,
    double? distanceM,
    double? meetupLat,
    double? meetupLng,
    String? meetupLabel,
    String? paceNote,
  }) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await SupabaseConfig.client
          .from('club_runs')
          .insert({
            'group_id': groupId,
            'created_by': uid,
            'title': title,
            'start_at': startAt.toUtc().toIso8601String(),
            'route_id': routeId,
            'distance_m': distanceM,
            'meetup_lat': meetupLat,
            'meetup_lng': meetupLng,
            'meetup_label': meetupLabel,
            'pace_note': paceNote,
          })
          .select(_sel)
          .single();
      return ClubRun.fromJson(Map<String, dynamic>.from(row), uid);
    } catch (e) {
      print('⚠️ createRun failed: $e');
      return null;
    }
  }

  /// Join ([going] = true) or leave ([going] = false) a run.
  Future<bool> setRsvp(String runId, bool going) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      if (going) {
        await SupabaseConfig.client.from('club_run_rsvps').upsert(
          {'run_id': runId, 'user_id': uid, 'status': 'going'},
          onConflict: 'run_id,user_id',
        );
      } else {
        await SupabaseConfig.client
            .from('club_run_rsvps')
            .delete()
            .eq('run_id', runId)
            .eq('user_id', uid);
      }
      return true;
    } catch (e) {
      print('⚠️ setRsvp failed: $e');
      return false;
    }
  }
}
