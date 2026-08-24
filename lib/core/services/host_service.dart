import 'dart:io';
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
          'capabilities': ['experience_host'],
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

  /// Deletes an experience and its associated schedules.
  Future<void> deleteExperience(String tableId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // 1. Get experience details for cleanup
    final experience = await _supabase
        .from('tables')
        .select()
        .eq('id', tableId)
        .eq('host_id', userId)
        .single();

    // 2. Delete associated schedules
    await _supabase
        .from('experience_schedules')
        .delete()
        .eq('table_id', tableId);

    // 3. Delete the experience from tables
    await _supabase
        .from('tables')
        .delete()
        .eq('id', tableId)
        .eq('host_id', userId);

    // 4. Cleanup storage images
    final images = (experience['images'] as List?)?.cast<String>() ?? [];
    for (final url in images) {
      try {
        final uri = Uri.parse(url);
        final fileName = uri.pathSegments.last;
        await _supabase.storage.from('experiences').remove([fileName]);
      } catch (_) {}
    }

    // 5. Cleanup video if present
    final videoUrl = experience['video_url'] as String?;
    if (videoUrl != null) {
      try {
        final uri = Uri.parse(videoUrl);
        final fileName = uri.pathSegments.last;
        await _supabase.storage.from('experience-videos').remove([fileName]);
      } catch (_) {}
    }
  }

  // ─── Events (Ticketed Events) ────────────────────────────────────────────
  // Backed by the shared web/app RPCs create_event / update_event /
  // set_event_published / manage_tiers (team_comms thread 198, #204/#206).
  // The RPCs run as the caller (SECURITY DEFINER) and validate that
  // organizer_id is an APPROVED partner the caller owns. Status at this
  // boundary is the clean 2-state vocab 'draft' | 'published'; the DB maps
  // published -> 'active' internally (a raw events.status read of a live event
  // returns 'active', not 'published').

  /// Returns all events organized by this partner, newest first, with their
  /// ticket tiers embedded.
  Future<List<Map<String, dynamic>>> getMyEvents(String partnerId) async {
    final response = await _supabase
        .from('events')
        .select('*, ticket_tiers(*)')
        .eq('organizer_id', partnerId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Uploads event images to a partner-owned prefix, per the storage RLS added
  /// in team_comms #204: an approved partner may write objects whose first path
  /// segment is their own partners.id. [bucket] is 'event-covers' (single cover)
  /// or 'event-images' (gallery). Returns the public URLs to pass into
  /// create_event / update_event.
  Future<List<String>> uploadEventMedia({
    required String partnerId,
    required String bucket,
    required List<File> files,
  }) async {
    final urls = <String>[];
    for (final file in files) {
      final ext = file.path.split('.').last;
      final path =
          '$partnerId/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
      await _supabase.storage.from(bucket).upload(path, file);
      urls.add(_supabase.storage.from(bucket).getPublicUrl(path));
    }
    return urls;
  }

  /// Creates an event via the shared `create_event` RPC. [payload] speaks the
  /// boundary vocabulary — send status 'draft' | 'published', category as an
  /// event_categories KEY (snake_case) or null, event_type as the events enum,
  /// seating_type 'general_admission', and optional tiers[] of
  /// {name, price, quantity_total, sort_order?} (omit -> auto GA tier).
  /// Returns { event_id, status } with status 'draft' | 'published'.
  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> payload) async {
    final response =
        await _supabase.rpc('create_event', params: {'payload': payload});
    return Map<String, dynamic>.from(response as Map);
  }

  /// Partial-updates an event via `update_event`. Only keys present in [payload]
  /// change; [payload] MUST include `event_id`. Event-detail fields only —
  /// tier changes go through [manageTiers]. Returns { event_id, status }.
  Future<Map<String, dynamic>> updateEvent(Map<String, dynamic> payload) async {
    final response =
        await _supabase.rpc('update_event', params: {'payload': payload});
    return Map<String, dynamic>.from(response as Map);
  }

  /// Publishes (true) or unpublishes (false) an event via `set_event_published`.
  /// Unpublish is blocked by the RPC once any ticket is sold (use a cancel flow
  /// instead). Returns { event_id, status } in the 'published' | 'draft' vocab.
  Future<Map<String, dynamic>> setEventPublished({
    required String eventId,
    required bool publish,
  }) async {
    final response = await _supabase.rpc('set_event_published', params: {
      'p_event_id': eventId,
      'p_publish': publish,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Add / update / remove ticket tiers via `manage_tiers`. The RPC applies
  /// REMOVE -> UPDATE -> ADD -> capacity check atomically (a failed guard rolls
  /// the whole batch back). [add] = [{name, price, quantity_total, sort_order?}],
  /// [update] = [{id, ...any of name|price|quantity_total|is_active|sort_order}]
  /// (partial), [remove] = [tierId,...]. Returns the fresh full tiers[] ordered
  /// by sort_order.
  Future<List<Map<String, dynamic>>> manageTiers({
    required String eventId,
    List<Map<String, dynamic>> add = const [],
    List<Map<String, dynamic>> update = const [],
    List<String> remove = const [],
  }) async {
    final response = await _supabase.rpc('manage_tiers', params: {
      'p_event_id': eventId,
      'p_add': add,
      'p_update': update,
      'p_remove': remove,
    });
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Returns a single event (with tiers) by id, or null. Used to refresh the
  /// per-event detail view after an edit/publish.
  Future<Map<String, dynamic>?> getEvent(String eventId) async {
    return _supabase
        .from('events')
        .select('*, ticket_tiers(*)')
        .eq('id', eventId)
        .maybeSingle();
  }

  /// Returns the attendee manifest for an event via the `get_event_attendees`
  /// RPC (team_comms #217). SECURITY DEFINER: validates the caller owns the
  /// event and resolves the logged-in buyer's profile with definer privileges,
  /// so registered-user tickets return their REAL name/email/avatar (reading
  /// `tickets` directly can't — the organizer token can't see buyer profiles).
  /// [status] = all | valid | checked_in | refunded; [search] matches
  /// ticket_number/name/email. Returns { total, limit, offset, attendees[] }.
  Future<Map<String, dynamic>> getEventAttendees(
    String eventId, {
    int limit = 50,
    int offset = 0,
    String status = 'all',
    String? search,
  }) async {
    final response = await _supabase.rpc('get_event_attendees', params: {
      'p_event_id': eventId,
      'p_limit': limit,
      'p_offset': offset,
      'p_status': status,
      'p_search': (search != null && search.trim().isNotEmpty)
          ? search.trim()
          : null,
    });
    return Map<String, dynamic>.from(response as Map);
  }

  /// Returns registrations for an event (the approvals inbox). RLS
  /// (organizers_read_event_registrations) lets the organizer read rows for
  /// their own events. Optionally filter by status (pending/approved/rejected…).
  Future<List<Map<String, dynamic>>> getEventRegistrations(
    String eventId, {
    String? status,
  }) async {
    // NOTE: no `tier:ticket_tiers(name)` embed — PostgREST can't resolve that
    // relationship (event_registrations.tier_id has no usable FK to
    // ticket_tiers) and returns 400. Tier display for a request, if needed,
    // is resolved client-side from the event's tiers.
    var query = _supabase
        .from('event_registrations')
        .select('*')
        .eq('event_id', eventId);
    if (status != null) query = query.eq('status', status);
    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Approves or rejects an event registration via the atomic
  /// `review-event-registration` edge function (team_comms #213). The function
  /// validates the caller owns the event, sets status/reviewed_by/reviewed_at,
  /// and fires ALL side-effects (free→issue ticket+QR email; paid→unlock
  /// purchase + "get your tickets" email; push; rejection email only if the
  /// organizer wrote custom copy). NEVER raw-UPDATE the row — there is no UPDATE
  /// trigger, so a direct update would skip the email/ticket. Only acts on a row
  /// currently 'pending' (409 otherwise — the double-tap guard).
  /// Returns { success, status: 'approved'|'rejected', registration_id }.
  Future<Map<String, dynamic>> reviewEventRegistration({
    required String registrationId,
    required bool approve,
    String? rejectionReason,
  }) async {
    final response = await _supabase.functions.invoke(
      'review-event-registration',
      body: {
        'registration_id': registrationId,
        'approve': approve,
        if (rejectionReason != null && rejectionReason.trim().isNotEmpty)
          'rejection_reason': rejectionReason.trim(),
      },
    );
    if (response.status != 200) {
      final data = response.data;
      throw Exception(data is Map
          ? (data['error'] ?? 'Failed to review request')
          : 'Failed to review request');
    }
    return Map<String, dynamic>.from(response.data as Map);
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

  /// Returns all schedules across all of this host's experiences.
  Future<List<Map<String, dynamic>>> getAllMySchedules(String partnerId) async {
    final response = await _supabase
        .from('experience_schedules')
        .select('*, experience:tables!inner!table_id(title, image_url, partner_id)')
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
        .inFilter('status', ['completed', 'refunded']);

    final expTransactions = List<Map<String, dynamic>>.from(expResponse);

    // 2. Fetch Event Earnings
    final eventResponse = await _supabase
        .from('transactions')
        .select(
            'gross_amount, platform_fee, payment_processing_fee, organizer_payout, status')
        .eq('partner_id', partnerId)
        .eq('status', 'completed');

    final eventTransactions = List<Map<String, dynamic>>.from(eventResponse);

    // 3. Fetch in-flight + settled payouts to subtract from available.
    // Lifecycle (team_comms #189): pending_request -> approved -> completed;
    // 'rejected'/'failed' return the funds to available so are excluded.
    // 'approved' MUST be here — admin approval is now the authoritative flip
    // (money is committed for disbursement), so omitting it overstated the
    // available balance.
    final payoutResponse = await _supabase
        .from('payouts')
        .select('amount, status')
        .eq('partner_id', partnerId)
        .inFilter('status', [
          'completed',
          'approved',
          'pending_request',
          'processing',
        ]);

    final payouts = List<Map<String, dynamic>>.from(payoutResponse);

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
      // Partner's true deductions = platform fee + the Xendit processing fee
      // they absorb at settlement (team_comms #170).
      final platformFee = (t['platform_fee'] as num?)?.toDouble() ?? 0;
      final procFee = (t['payment_processing_fee'] as num?)?.toDouble() ?? 0;
      totalFees += platformFee + procFee;
      // organizer_payout does NOT exclude the processing fee, so subtract it
      // here to get what actually lands in the partner wallet. Historical rows
      // (pre webhook v77) have procFee = 0, so they're unaffected.
      final payout = (t['organizer_payout'] as num?)?.toDouble() ?? 0;
      totalPayout += payout - procFee;
    }

    // 4. Sum all payouts that are completed or in-progress
    double totalWithdrawn = 0;
    for (final p in payouts) {
      totalWithdrawn += (p['amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'total_gross': totalGross,
      'total_fees': totalFees,
      'total_payout': totalPayout,  // All-time net earnings (minus refunds)
      'available_balance': totalPayout - totalWithdrawn,  // What's left to withdraw
      'total_withdrawn': totalWithdrawn,
      'transaction_count': expTransactions.length + eventTransactions.length,
    };
  }

  /// Returns transaction history for this host partner (earnings + refunds).
  Future<List<Map<String, dynamic>>> getTransactionHistory(
    String partnerId, {
    int offset = 0,
    int limit = 20,
  }) async {
    // Fetch experience transactions with experience title
    final expResponse = await _supabase
        .from('experience_transactions')
        .select('id, gross_amount, platform_fee, host_payout, status, created_at, purchase_intent_id, experience:tables!table_id(title)')
        .eq('partner_id', partnerId)
        .inFilter('status', ['completed', 'refunded'])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final expTransactions = List<Map<String, dynamic>>.from(expResponse);

    // Fetch event transactions with event title
    final eventResponse = await _supabase
        .from('transactions')
        .select('id, gross_amount, platform_fee, payment_processing_fee, organizer_payout, status, created_at, purchase_intent_id, event:events!event_id(title)')
        .eq('partner_id', partnerId)
        .inFilter('status', ['completed', 'refunded'])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final eventTransactions = List<Map<String, dynamic>>.from(eventResponse);

    // Normalize and merge
    final List<Map<String, dynamic>> all = [];

    for (final t in expTransactions) {
      all.add({
        'id': t['id'],
        'title': (t['experience'] as Map<String, dynamic>?)?['title'] ?? 'Experience',
        'amount': (t['host_payout'] as num?)?.toDouble() ?? 0,
        'gross_amount': (t['gross_amount'] as num?)?.toDouble() ?? 0,
        'platform_fee': (t['platform_fee'] as num?)?.toDouble() ?? 0,
        'status': t['status'],
        'type': 'experience',
        'created_at': t['created_at'],
        'intent_id': t['purchase_intent_id'],
      });
    }

    for (final t in eventTransactions) {
      // Net to wallet excludes the processing fee the partner absorbs (#170).
      final payout = (t['organizer_payout'] as num?)?.toDouble() ?? 0;
      final procFee = (t['payment_processing_fee'] as num?)?.toDouble() ?? 0;
      all.add({
        'id': t['id'],
        'title': (t['event'] as Map<String, dynamic>?)?['title'] ?? 'Event',
        'amount': payout - procFee,
        'gross_amount': (t['gross_amount'] as num?)?.toDouble() ?? 0,
        'platform_fee': (t['platform_fee'] as num?)?.toDouble() ?? 0,
        'status': t['status'],
        'type': 'event',
        'created_at': t['created_at'],
        'intent_id': t['purchase_intent_id'],
      });
    }

    // Sort by date descending
    all.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    return all;
  }

  /// Returns payout history for this host.
  Future<List<Map<String, dynamic>>> getPayoutHistory(
    String partnerId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final response = await _supabase
        .from('payouts')
        .select()
        .eq('partner_id', partnerId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);


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

  // ─── Wallet (XenPlatform) ─────────────────────────────────────────────

  /// Fetches the partner's real Xendit sub-wallet balance via edge function.
  /// Returns { available_balance, pending_settlement, platform_fee_receivable,
  ///           currency, has_subaccount, xendit_account_id }.
  Future<Map<String, dynamic>> getSubaccountBalance(String partnerId) async {
    final response = await _supabase.functions.invoke(
      'get-subaccount-balance',
      body: {'partner_id': partnerId},
    );

    if (response.status != 200) {
      final error = response.data;
      throw Exception(error?['error'] ?? 'Failed to fetch wallet balance');
    }

    return Map<String, dynamic>.from(response.data);
  }

  /// Fetches the partner's wallet info from the partners table (lightweight, no Xendit call).
  /// Returns { xendit_account_id, platform_fee_receivable, kyc_status }.
  Future<Map<String, dynamic>> getWalletInfo(String partnerId) async {
    final response = await _supabase
        .from('partners')
        .select('xendit_account_id, platform_fee_receivable, kyc_status')
        .eq('id', partnerId)
        .single();

    return response;
  }

  /// Calls the topup-wallet edge function to create a payment link.
  /// Returns the response with payment_url.
  Future<Map<String, dynamic>> topUpWallet({
    required String partnerId,
    required double amount,
  }) async {
    final response = await _supabase.functions.invoke(
      'topup-wallet',
      body: {
        'partner_id': partnerId,
        'amount': amount,
      },
    );

    if (response.status != 200) {
      final error = response.data;
      throw Exception(error?['error'] ?? 'Failed to create top-up payment');
    }

    return Map<String, dynamic>.from(response.data);
  }
}
