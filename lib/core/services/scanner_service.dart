import 'package:bitemates/core/config/supabase_config.dart';

/// Organizer-side ticket scanning.
///
/// Authorization is enforced server-side by the `scan_ticket` RPC
/// (SECURITY DEFINER) — see team_comms #161. The gating here is cosmetic: it
/// only decides whether to *surface* the scanner. The scan-capable role set
/// mirrors the RPC: owner, manager, scanner, cashier (cashier is forward-
/// compatible — not in the `partner_role` enum yet, harmless until it lands).
class ScannerService {
  static const List<String> scanRoles = [
    'owner',
    'manager',
    'scanner',
    'cashier',
  ];

  /// Partner ids the current user may scan for: partners they own, plus active
  /// team memberships with an operational role. Empty list ⇒ hide the scanner.
  Future<List<String>> getScannablePartnerIds() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return [];

    final ids = <String>{};
    try {
      // Owner
      final owned = await SupabaseConfig.client
          .from('partners')
          .select('id')
          .eq('user_id', userId);
      for (final row in (owned as List)) {
        ids.add(row['id'] as String);
      }

      // Operational team member. We filter roles in Dart rather than via
      // .inFilter() because 'cashier' isn't in the partner_role enum yet —
      // sending it to Postgres throws 22P02 (invalid enum value). Filtering
      // client-side stays forward-compatible: when web adds 'cashier' to the
      // enum, it starts matching automatically with no app change.
      final memberships = await SupabaseConfig.client
          .from('partner_team_members')
          .select('partner_id, role')
          .eq('user_id', userId)
          .eq('is_active', true);
      for (final row in (memberships as List)) {
        if (scanRoles.contains(row['role'])) {
          ids.add(row['partner_id'] as String);
        }
      }
    } catch (e) {
      print('⚠️ getScannablePartnerIds failed: $e');
    }
    return ids.toList();
  }

  /// Events the user can scan: belonging to their partners, still relevant
  /// (active/hidden) and not finished before today. Newest start first.
  Future<List<Map<String, dynamic>>> getScannableEvents(
    List<String> partnerIds,
  ) async {
    if (partnerIds.isEmpty) return [];
    try {
      final todayMidnight = DateTime.now()
          .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0)
          .toIso8601String();

      final response = await SupabaseConfig.client
          .from('events')
          .select(
            'id, title, start_datetime, venue_name, cover_image_url, '
            'tickets_sold, capacity',
          )
          .inFilter('organizer_id', partnerIds)
          .inFilter('status', ['active', 'hidden'])
          .gte('start_datetime', todayMidnight)
          .order('start_datetime', ascending: true);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('⚠️ getScannableEvents failed: $e');
      return [];
    }
  }

  /// Calls the server-side `scan_ticket`. [code] is the raw QR payload
  /// (`ticketId:eventId:USERorGUEST`); the RPC matches it against ticket id /
  /// qr_code / ticket_number. Pass [eventId] so the RPC can flag "Wrong Event".
  ///
  /// Returns the RPC jsonb: { success, message, details?, ticket? }.
  Future<Map<String, dynamic>> scanTicket({
    required String code,
    required String eventId,
  }) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) {
      return {'success': false, 'message': 'Not signed in'};
    }
    try {
      final result = await SupabaseConfig.client.rpc(
        'scan_ticket',
        params: {
          'p_code': code,
          'p_user_id': userId,
          'p_event_id': eventId,
        },
      );
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      print('⚠️ scanTicket failed: $e');
      return {'success': false, 'message': 'Scan failed', 'details': '$e'};
    }
  }
}
