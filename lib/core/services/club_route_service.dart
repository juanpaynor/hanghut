import 'package:bitemates/core/config/supabase_config.dart';

/// A saved run-club route (row of `club_routes`).
class ClubRoute {
  final String id;
  final String groupId;
  final String name;

  /// GeoJSON LineString: { type: 'LineString', coordinates: [[lng,lat], ...] }.
  final Map<String, dynamic>? path;
  final double? distanceM;
  final DateTime? createdAt;

  const ClubRoute({
    required this.id,
    required this.groupId,
    required this.name,
    this.path,
    this.distanceM,
    this.createdAt,
  });

  factory ClubRoute.fromJson(Map<String, dynamic> j) => ClubRoute(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        name: (j['name'] as String?) ?? 'Route',
        path: j['path'] == null
            ? null
            : Map<String, dynamic>.from(j['path'] as Map),
        distanceM: (j['distance_m'] as num?)?.toDouble(),
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'].toString())?.toLocal(),
      );
}

/// Data layer for run-club routes. RLS enforces membership/roles server-side;
/// see team_comms #280 for the contract.
class ClubRouteService {
  /// Persists a route created in the in-app route creator. Returns the saved
  /// row, or null on failure.
  Future<ClubRoute?> createRoute({
    required String groupId,
    required String name,
    required Map<String, dynamic> path,
    List<dynamic>? waypoints,
    double? distanceM,
  }) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await SupabaseConfig.client
          .from('club_routes')
          .insert({
            'group_id': groupId,
            'created_by': uid,
            'name': name,
            'path': path,
            'waypoints': waypoints,
            'distance_m': distanceM,
          })
          .select()
          .single();
      return ClubRoute.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      print('⚠️ createRoute failed: $e');
      return null;
    }
  }

  /// Lists a club's routes, newest first.
  Future<List<ClubRoute>> listRoutes(String groupId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('club_routes')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => ClubRoute.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      print('⚠️ listRoutes failed: $e');
      return [];
    }
  }

  /// Deletes a route (RLS allows the creator or a club owner/admin).
  Future<bool> deleteRoute(String id) async {
    try {
      await SupabaseConfig.client.from('club_routes').delete().eq('id', id);
      return true;
    } catch (e) {
      print('⚠️ deleteRoute failed: $e');
      return false;
    }
  }
}
