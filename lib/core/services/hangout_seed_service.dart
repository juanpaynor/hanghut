import 'package:flutter/foundation.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// Reads and answers system-proposed hangouts.
///
/// See [HangoutSeed] for what a seed is and why it carries no identities.
class HangoutSeedService {
  /// Cached for the process lifetime, like the nudge.
  ///
  /// `_fetched` is tracked separately from `_cached` so "no seed for this
  /// user" — the common case — is remembered rather than re-queried on every
  /// rebuild of every surface that mounts the card.
  static HangoutSeed? _cached;
  static bool _fetched = false;

  static void invalidate() {
    _cached = null;
    _fetched = false;
  }

  /// The caller's current proposal, or null.
  ///
  /// Never throws: the seed is an enhancement to screens that must work
  /// without it, so a failure degrades to showing nothing.
  Future<HangoutSeed?> fetch({bool force = false}) async {
    if (_fetched && !force) return _cached;
    try {
      // get_my_hangout_offer, not get_my_hangout_seed: the event-anchored
      // rewrite changed the return shape, and Postgres cannot change a
      // function's return type without a DROP. The old function still exists
      // and is unused.
      final rows = await SupabaseConfig.client.rpc('get_my_hangout_offer');
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      _cached = HangoutSeed.fromJson(
        row is Map ? Map<String, dynamic>.from(row) : null,
      );
      _fetched = true;
      return _cached;
    } catch (e) {
      debugPrint('⚠️ get_my_hangout_seed failed: $e');
      // Not setting _fetched: a transient failure should be retried, unlike
      // a genuine empty result.
      return null;
    }
  }

  /// Says yes or no.
  ///
  /// On yes, [SeedResponse.isHost] says which of two different things happens
  /// next — the caller opens the create flow pre-filled, or joins the hangout
  /// somebody already made. The server decides, not the client: two people
  /// tapping at once must not both believe they are hosting.
  Future<SeedResponse> respond(String seedId, {required bool isIn}) async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'respond_to_hangout_seed',
        params: {'p_seed_id': seedId, 'p_response': isIn ? 'in' : 'out'},
      );
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      invalidate();
      if (row is! Map) {
        return const SeedResponse(ok: false, message: 'Something went wrong');
      }
      return SeedResponse(
        ok: row['ok'] as bool? ?? false,
        isHost: row['is_host'] as bool? ?? false,
        claimedTableId: (row['claimed_table_id'] as String?)?.trim(),
        message: (row['message'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('⚠️ respond_to_hangout_seed failed: $e');
      return const SeedResponse(
        ok: false,
        message: 'Could not save that. Try again.',
      );
    }
  }

  /// Binds the hangout the host just created to the seed, and invites
  /// everyone else who said yes.
  ///
  /// Called AFTER creation so the seed is only ever marked claimed against a
  /// table that exists. A failure here leaves the hangout intact and merely
  /// un-linked, which is why it reports rather than throws.
  Future<SeedClaim> claim({
    required String seedId,
    required String tableId,
  }) async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'claim_hangout_seed',
        params: {'p_seed_id': seedId, 'p_table_id': tableId},
      );
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      invalidate();
      if (row is! Map) {
        return const SeedClaim(ok: false, invited: 0, message: '');
      }
      return SeedClaim(
        ok: row['ok'] as bool? ?? false,
        invited: (row['invited'] as num?)?.toInt() ?? 0,
        message: (row['message'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('⚠️ claim_hangout_seed failed: $e');
      return const SeedClaim(ok: false, invited: 0, message: '');
    }
  }
}

/// The outcome of saying yes or no to a proposal.
class SeedResponse {
  final bool ok;

  /// True when this user won the race and should open the create flow.
  final bool isHost;

  /// Set when somebody else already claimed it — there is a hangout to join.
  final String? claimedTableId;

  final String message;

  const SeedResponse({
    required this.ok,
    this.isHost = false,
    this.claimedTableId,
    this.message = '',
  });
}

/// The outcome of binding a created hangout to its seed.
class SeedClaim {
  final bool ok;

  /// How many other people were invited to the new hangout.
  final int invited;

  final String message;

  const SeedClaim({
    required this.ok,
    required this.invited,
    required this.message,
  });
}
