import 'package:bitemates/core/config/supabase_config.dart';

class HostService {
  final _supabase = SupabaseConfig.client;

  // ─── Partner / Host Status ───────────────────────────────────────────────

  /// Returns the current user's partner record, or null if not a host.
  Future<Map<String, dynamic>?> getMyPartnerProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _supabase
        .from('partners')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    return response;
  }

  /// Creates a new partner application (status = 'pending').
  Future<Map<String, dynamic>> applyAsHost({
    required String businessName,
    required String description,
    required String representativeName,
    required String contactNumber,
    required String workEmail,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('partners')
        .insert({
          'user_id': userId,
          'business_name': businessName,
          'description': description,
          'representative_name': representativeName,
          'contact_number': contactNumber,
          'work_email': workEmail,
          'status': 'pending',
          'kyc_status': 'not_started',
        })
        .select()
        .single();

    return response;
  }

  // ─── Experiences (My Listings) ───────────────────────────────────────────

  /// Returns all experiences created by this host partner.
  Future<List<Map<String, dynamic>>> getMyExperiences(String partnerId) async {
    final response = await _supabase
        .from('tables')
        .select('*, schedules:experience_schedules(count)')
        .eq('partner_id', partnerId)
        .eq('is_experience', true)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Creates a new experience listing.
  Future<Map<String, dynamic>> createExperience({
    required String partnerId,
    required String title,
    required String description,
    required String experienceType,
    required List<String> images,
    String? videoUrl,
    required List<String> requirements,
    required List<String> includedItems,
    required double pricePerPerson,
    required String currency,
    required int maxGuests,
    required String locationName,
    required double latitude,
    required double longitude,
    List<Map<String, dynamic>>? itinerary,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('tables')
        .insert({
          'host_id': userId,
          'partner_id': partnerId,
          'title': title,
          'description': description,
          'experience_type': experienceType,
          'images': images,
          'video_url': videoUrl,
          'requirements': requirements,
          'included_items': includedItems,
          'price_per_person': pricePerPerson,
          'currency': currency,
          'max_guests': maxGuests,
          'location_name': locationName,
          'latitude': latitude,
          'longitude': longitude,
          'itinerary': itinerary,
          'is_experience': true,
          'verified_by_hanghut': false, // Requires admin review
          'status': 'open',
          'datetime': DateTime.now()
              .add(const Duration(days: 365))
              .toIso8601String(), // Push far to future for experiences
        })
        .select()
        .single();

    return response;
  }

  /// Updates an existing experience listing.
  Future<Map<String, dynamic>> updateExperience({
    required String tableId,
    required String title,
    required String description,
    required String experienceType,
    required List<String> images,
    String? videoUrl,
    required List<String> requirements,
    required List<String> includedItems,
    required double pricePerPerson,
    required String currency,
    required int maxGuests,
    required String locationName,
    required double latitude,
    required double longitude,
    List<Map<String, dynamic>>? itinerary,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('tables')
        .update({
          'title': title,
          'description': description,
          'experience_type': experienceType,
          'images': images,
          'video_url': videoUrl,
          'requirements': requirements,
          'included_items': includedItems,
          'price_per_person': pricePerPerson,
          'currency': currency,
          'max_guests': maxGuests,
          'location_name': locationName,
          'latitude': latitude,
          'longitude': longitude,
          'itinerary': itinerary,
          'datetime': DateTime.now()
              .add(const Duration(days: 365))
              .toIso8601String(), // Refresh expiration
        })
        .eq('id', tableId)
        .eq('host_id', userId) // Security check
        .select()
        .single();

    return response;
  }
  // ─── Schedules ───────────────────────────────────────────────────────────

  /// Returns all schedules for a specific experience.
  Future<List<Map<String, dynamic>>> getSchedules(String tableId) async {
    final response = await _supabase
        .from('experience_schedules')
        .select()
        .eq('table_id', tableId)
        .order('start_time', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Returns all upcoming schedules across all of this host's experiences.
  Future<List<Map<String, dynamic>>> getAllMySchedules(String partnerId) async {
    final response = await _supabase
        .from('experience_schedules')
        .select('*, experience:tables!table_id(title, image_url, partner_id)')
        .eq('tables.partner_id', partnerId)
        .order('start_time', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Adds a new time slot to an experience.
  Future<void> addSchedule({
    required String tableId,
    required DateTime startTime,
    required DateTime endTime,
    required int maxGuests,
    double? pricePerPerson,
  }) async {
    await _supabase.from('experience_schedules').insert({
      'table_id': tableId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'max_guests': maxGuests,
      'current_guests': 0,
      'price_per_person': pricePerPerson,
      'status': 'open',
    });
  }

  /// Cancels a schedule slot.
  Future<void> cancelSchedule(String scheduleId) async {
    await _supabase
        .from('experience_schedules')
        .update({'status': 'cancelled'})
        .eq('id', scheduleId);
  }

  /// Deletes a schedule slot entirely.
  Future<void> deleteSchedule(String scheduleId) async {
    await _supabase.from('experience_schedules').delete().eq('id', scheduleId);
  }

  // ─── Bookings & Payments ─────────────────────────────────────────────────

  /// Returns all completed bookings for a specific schedule slot (the Guest Manifest).
  Future<List<Map<String, dynamic>>> getScheduleBookings(
    String scheduleId,
  ) async {
    final response = await _supabase
        .from('experience_purchase_intents')
        .select('*, experience:tables!table_id(title, partner_id)')
        .eq('schedule_id', scheduleId)
        .eq('status', 'completed')
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Marks a specific booking (guest) as checked in.
  Future<void> checkInGuest(String intentId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final result = await _supabase
        .from('experience_purchase_intents')
        .update({
          'check_in_status': 'checked_in',
          'checked_in_at': DateTime.now().toIso8601String(),
          'checked_in_by': user.id,
        })
        .eq('id', intentId)
        .select();

    if (result.isEmpty) {
      throw Exception(
        'Permission denied or purchase intent not found. Please check Supabase RLS.',
      );
    }
  }

  /// Marks a specific booking (guest) as no-show.
  Future<void> markGuestNoShow(String intentId) async {
    final result = await _supabase
        .from('experience_purchase_intents')
        .update({'check_in_status': 'no_show'})
        .eq('id', intentId)
        .select();

    if (result.isEmpty) {
      throw Exception(
        'Permission denied or purchase intent not found. Please check Supabase RLS.',
      );
    }
  }

  /// Returns all completed bookings across all experiences for this partner.
  Future<List<Map<String, dynamic>>> getMyBookings(String partnerId) async {
    // Get all table IDs for this partner
    final tables = await _supabase
        .from('tables')
        .select('id')
        .eq('partner_id', partnerId)
        .eq('is_experience', true);

    if (tables.isEmpty) return [];

    final tableIds = (tables as List).map((t) => t['id'] as String).toList();

    final response = await _supabase
        .from('experience_purchase_intents')
        .select(
          '*, schedule:experience_schedules(start_time, end_time), experience:tables!table_id(title)',
        )
        .inFilter('table_id', tableIds)
        .eq('status', 'completed')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Earnings ────────────────────────────────────────────────────────────

  /// Returns earnings summary for this host partner (Events + Experiences).
  Future<Map<String, dynamic>> getEarningsSummary(String partnerId) async {
    // 1. Fetch Experience Earnings
    final expResponse = await _supabase
        .from('experience_transactions')
        .select('gross_amount, platform_fee, host_payout, status')
        .eq('partner_id', partnerId)
        .eq('status', 'completed');

    final expTransactions = List<Map<String, dynamic>>.from(expResponse);

    // 2. Fetch Event Earnings
    final eventResponse = await _supabase
        .from('transactions')
        .select('gross_amount, platform_fee, organizer_payout, status')
        .eq('partner_id', partnerId)
        .eq('status', 'completed');

    final eventTransactions = List<Map<String, dynamic>>.from(eventResponse);

    double totalGross = 0;
    double totalFees = 0;
    double totalPayout = 0;

    for (final t in expTransactions) {
      totalGross += (t['gross_amount'] as num?)?.toDouble() ?? 0;
      totalFees += (t['platform_fee'] as num?)?.toDouble() ?? 0;
      totalPayout += (t['host_payout'] as num?)?.toDouble() ?? 0;
    }

    for (final t in eventTransactions) {
      totalGross += (t['gross_amount'] as num?)?.toDouble() ?? 0;
      totalFees += (t['platform_fee'] as num?)?.toDouble() ?? 0;
      totalPayout += (t['organizer_payout'] as num?)?.toDouble() ?? 0;
    }

    return {
      'total_gross': totalGross,
      'total_fees': totalFees,
      'total_payout': totalPayout,
      'transaction_count': expTransactions.length + eventTransactions.length,
    };
  }

  /// Returns payout history for this host.
  Future<List<Map<String, dynamic>>> getPayoutHistory(String partnerId) async {
    final response = await _supabase
        .from('payouts')
        .select()
        .eq('partner_id', partnerId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Requests a payout.
  Future<void> requestPayout({
    required String partnerId,
    required double amount,
    required String channelCode,
    required String bankAccountNumber,
    required String bankAccountName,
  }) async {
    // Note: The Edge function will ignore bankName/Account and look up the primary
    // bank_accounts row directly, but we keep this signature for backward compatibility
    // if other screens call it until the cloud function is fully updated.
    await _supabase.from('payouts').insert({
      'partner_id': partnerId,
      'amount': amount,
      'currency': 'PHP',
      'bank_name': channelCode,
      'bank_account_number': bankAccountNumber,
      'bank_account_name': bankAccountName,
      'status': 'pending_request',
    });
  }

  // ─── Bank Accounts ───────────────────────────────────────────────────────

  /// Fetches all bank accounts for a partner.
  Future<List<Map<String, dynamic>>> getBankAccounts(String partnerId) async {
    final response = await _supabase
        .from('bank_accounts')
        .select()
        .eq('partner_id', partnerId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Adds a new bank account.
  Future<void> addBankAccount({
    required String partnerId,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
  }) async {
    // If it's the first account, make it primary automatically
    final existing = await getBankAccounts(partnerId);
    final isPrimary = existing.isEmpty;

    await _supabase.from('bank_accounts').insert({
      'partner_id': partnerId,
      'bank_code': bankCode,
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_holder_name': accountHolderName,
      'is_primary': isPrimary,
    });
  }

  /// Deletes a bank account.
  Future<void> deleteBankAccount(String accountId) async {
    await _supabase.from('bank_accounts').delete().eq('id', accountId);
  }

  /// Sets an account to be the primary payout account.
  Future<void> setPrimaryBankAccount(String accountId, String partnerId) async {
    // 1. Unset all primary accounts for this partner
    await _supabase
        .from('bank_accounts')
        .update({'is_primary': false})
        .eq('partner_id', partnerId);

    // 2. Set the requested account as primary
    await _supabase
        .from('bank_accounts')
        .update({'is_primary': true})
        .eq('id', accountId);
  }
}
