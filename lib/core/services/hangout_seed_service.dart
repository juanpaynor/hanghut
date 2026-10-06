import 'package:flutter/foundation.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/activity/models/hangout_seed.dart';

/// Reads and answers system-made hangout suggestions.
///
/// See [HangoutSeed] for what a suggestion is and why it carries no
/// identities.
class HangoutSeedService {
  /// Cached for the process lifetime.
  ///
  /// `_fetched` is separate from `_cached` so "no suggestion for this user" —
  /// the common case — is remembered rather than re-queried on every rebuild
  /// of every surface that mounts the card.
  static HangoutSeed? _cached;
  static bool _fetched = false;

  static void invalidate() {
    _cached = null;
    _fetched = false;
  }

  /// The caller's current suggestion, or null.
  ///
  /// Never throws: the suggestion is an enhancement to screens that must work
  /// without it, so a failure degrades to showing nothing.
  Future<HangoutSeed?> fetch({bool force = false}) async {
    if (_fetched && !force) return _cached;
    try {
      final rows =
          await SupabaseConfig.client.rpc('get_my_hangout_suggestion');
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      _cached = HangoutSeed.fromJson(
        row is Map ? Map<String, dynamic>.from(row) : null,
      );
      _fetched = true;
      return _cached;
    } catch (e) {
      debugPrint('⚠️ get_my_hangout_suggestion failed: $e');
      // Not setting _fetched: a transient failure should be retried, unlike a
      // genuine empty result.
      return null;
    }
  }

  /// Says yes. One call does everything.
  ///
  /// The hangout is created server-side with this user as host — no create
  /// form, which was the drop-off the suggestion exists to remove. Everyone
  /// else who already said yes is invited to it.
  ///
  /// The server decides whether this user hosts or joins: two people tapping
  /// at the same instant must not both be told they are hosting, and only the
  /// claim's guarded UPDATE can settle that.
  Future<SeedAccept> accept(String seedId) async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'accept_hangout_suggestion',
        params: {'p_seed_id': seedId},
      );
      final row = (rows is List && rows.isNotEmpty) ? rows.first : null;
      invalidate();
      if (row is! Map) {
        return const SeedAccept(ok: false, message: 'Something went wrong');
      }
      return SeedAccept(
        ok: row['ok'] as bool? ?? false,
        isHost: row['is_host'] as bool? ?? false,
        tableId: (row['table_id'] as String?)?.trim(),
        invited: (row['invited'] as num?)?.toInt() ?? 0,
        message: (row['message'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('⚠️ accept_hangout_suggestion failed: $e');
      return const SeedAccept(
        ok: false,
        message: 'Could not set that up. Try again.',
      );
    }
  }

  /// Says no. Best-effort — the card is dismissed either way, because making
  /// someone tap "no thanks" twice is worse than losing the record of it.
  Future<void> decline(String seedId) async {
    try {
      await SupabaseConfig.client.rpc(
        'decline_hangout_suggestion',
        params: {'p_seed_id': seedId},
      );
    } catch (e) {
      debugPrint('⚠️ decline_hangout_suggestion failed: $e');
    } finally {
      invalidate();
    }
  }
}

/// The outcome of saying yes.
class SeedAccept {
  final bool ok;

  /// True when this user won the race and is hosting the new hangout.
  final bool isHost;

  /// The hangout — newly created if hosting, the existing one if joining.
  final String? tableId;

  /// How many others were invited, when hosting.
  final int invited;

  final String message;

  const SeedAccept({
    required this.ok,
    this.isHost = false,
    this.tableId,
    this.invited = 0,
    this.message = '',
  });
}
