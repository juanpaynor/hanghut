import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/models/ticket_tier.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/screens/ticket_success_screen.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'dart:async';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:bitemates/features/ticketing/widgets/registration_questions_form.dart';
import 'package:bitemates/core/theme/app_theme.dart';
// GEOFENCING DISABLED for Android review — uncomment to re-enable
// import 'package:workmanager/workmanager.dart';

class EventPurchaseScreen extends StatefulWidget {
  final Event event;

  /// When provided, the user has already submitted (and been approved for) a
  /// registration request. Skip the form/RPC and go straight to payment using
  /// this id so the ticket is linked to it.
  final String? existingRegistrationId;

  const EventPurchaseScreen({
    super.key,
    required this.event,
    this.existingRegistrationId,
  });

  @override
  State<EventPurchaseScreen> createState() => _EventPurchaseScreenState();
}

class _EventPurchaseScreenState extends State<EventPurchaseScreen>
    with WidgetsBindingObserver {
  int _quantity = 1;
  int _currentStep = 0; // Multi-step checkout: Ticket / Details / Questions / Review
  bool _isLoading = false;
  String? _currentPurchaseIntentId;
  Timer? _pollingTimer;
  bool _isPaymentInProgress = false;
  int _consecutiveErrors = 0;
  bool _subscribedToNewsletter = true;

  // Event Details (for Fees)
  Event? _fullEvent;
  bool _isLoadingEventDetails = false;

  // Real availability (counted from tickets table)
  int _realTicketsAvailable = 10; // default max per person

  // New State for Tiers & Promos
  List<TicketTier> _tiers = [];
  TicketTier? _selectedTier;
  bool _isLoadingTiers = true;

  final _promoCodeController = TextEditingController();
  bool _isCheckingPromo = false;
  String? _appliedPromoCode;
  double _promoDiscountAmount = 0;
  String? _promoError;

  // Subscriber discount + early access
  Map<String, dynamic>? _subscriberDiscount;
  bool _isActiveSubscriber = false;

  // Contact Details Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _completePhoneNumber = '';
  final _formKey = GlobalKey<FormState>();

  // Registration questions
  List<Map<String, dynamic>> _registrationQuestions = [];
  Map<String, dynamic> _registrationAnswers = {};
  String? _registrationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registrationId = widget.existingRegistrationId;
    _fetchUserProfile(); // Pre-fill if logged in
    _fetchTicketTiers();
    _checkEventDetails();
    _fetchRealAvailability();
    _loadSubscriberData();
    // Skip loading questions when paying for an already-approved registration —
    // the answers were submitted in the original request.
    if (_registrationId == null) {
      _loadRegistrationQuestions();
    }
  }

  Future<void> _loadRegistrationQuestions() async {
    try {
      final response = await SupabaseConfig.client
          .from('registration_questions')
          .select()
          .eq('event_id', widget.event.id)
          .order('display_order', ascending: true);
      if (mounted) {
        setState(() {
          _registrationQuestions =
              List<Map<String, dynamic>>.from(response as List);
        });
      }
    } catch (e) {
      print('⚠️ Could not load registration questions: $e');
    }
  }

  Future<void> _loadSubscriberData() async {
    if (SupabaseConfig.client.auth.currentUser == null) return;
    try {
      final needsSubCheck = widget.event.subscriberEarlyAccessHours != null ||
          widget.event.isSubscriberOnly;
      final Future<dynamic> discountFuture = SupabaseConfig.client.rpc(
        'get_subscriber_event_discount',
        params: {'p_event_id': widget.event.id},
      );
      final Future<dynamic> subFuture = needsSubCheck
          ? SupabaseConfig.client.rpc(
              'is_active_subscriber',
              params: {'p_partner_id': widget.event.organizerId},
            )
          : Future.value(false);
      final results = await Future.wait([discountFuture, subFuture]);
      if (!mounted) return;
      setState(() {
        final discount = results[0];
        if (discount != null) {
          _subscriberDiscount = Map<String, dynamic>.from(discount as Map);
        }
        _isActiveSubscriber = results[1] == true;
      });
    } catch (e) {
      debugPrint('⚠️ Subscriber data load failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    PushNotificationService.suppressNotifications = false; // Always clear

    // GEOFENCING DISABLED for Android review — uncomment to re-enable
    // Workmanager().registerPeriodicTask(
    //   'geofence-check',
    //   'geofenceTask',
    //   frequency: const Duration(minutes: 15),
    //   constraints: Constraints(networkType: NetworkType.connected),
    // );

    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!_isPaymentInProgress || _currentPurchaseIntentId == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background (payment browser opening) — PAUSE polling
      // to prevent network errors that will cause ANR on resume
      print('⏸️ App backgrounded during payment — pausing polling timer');
      _pollingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // App returned from payment browser — do a fresh check
      print('🔄 App resumed from payment browser — checking status');
      _consecutiveErrors = 0;

      // Longer delay to let Mapbox and other services stabilize first
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted || !_isPaymentInProgress) return;
        _checkPaymentStatusOnce();
      });
    }
  }

  /// One-shot status check when app resumes from payment browser
  Future<void> _checkPaymentStatusOnce() async {
    try {
      final purchase = await SupabaseConfig.client
          .from('purchase_intents')
          .select('status')
          .eq('id', _currentPurchaseIntentId!)
          .single();

      final status = purchase['status'] as String;
      print('🔄 Resume check: status = $status');

      if (status == 'completed') {
        _pollingTimer?.cancel();
        _isPaymentInProgress = false;
        PushNotificationService.suppressNotifications = false;
        if (mounted) {
          Navigator.pop(context); // Close processing dialog
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TicketSuccessScreen(
                purchaseIntentId: _currentPurchaseIntentId!,
              ),
            ),
          );
        }
      } else if (status == 'failed' || status == 'expired') {
        _pollingTimer?.cancel();
        _isPaymentInProgress = false;
        PushNotificationService.suppressNotifications = false;
        if (mounted) {
          Navigator.pop(context);
          _showErrorDialog('Payment Failed', 'The payment was not completed.');
        }
      } else {
        // Still pending — restart polling timer
        print('🔄 Payment still pending — restarting polling');
        _restartPolling();
      }
    } catch (e) {
      print('⚠️ Resume status check error: $e');
      // Restart polling anyway — it will keep trying
      _restartPolling();
    }
  }

  /// Restart the polling timer after resume (only if payment still in progress)
  void _restartPolling() {
    if (!_isPaymentInProgress || !mounted) return;
    _pollingTimer?.cancel(); // Safety cancel
    _consecutiveErrors = 0;

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        _isPaymentInProgress = false;
        return;
      }

      try {
        final purchase = await SupabaseConfig.client
            .from('purchase_intents')
            .select('status')
            .eq('id', _currentPurchaseIntentId!)
            .single();

        _consecutiveErrors = 0;
        final status = purchase['status'] as String;

        if (status == 'completed') {
          timer.cancel();
          _isPaymentInProgress = false;
          if (mounted) {
            Navigator.pop(context);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => TicketSuccessScreen(
                  purchaseIntentId: _currentPurchaseIntentId!,
                ),
              ),
            );
          }
        } else if (status == 'failed' || status == 'expired') {
          timer.cancel();
          _isPaymentInProgress = false;
          if (mounted) {
            Navigator.pop(context);
            _showErrorDialog(
              'Payment Failed',
              'The payment was not completed.',
            );
          }
        }
      } catch (e) {
        _consecutiveErrors++;
        print('⚠️ Polling error ($_consecutiveErrors/10): $e');
        if (_consecutiveErrors >= 10) {
          timer.cancel();
          _isPaymentInProgress = false;
          if (mounted) {
            Navigator.pop(context);
            _showTimeoutDialog();
          }
        }
      }
    });
  }

  Future<void> _fetchTicketTiers() async {
    try {
      final response = await SupabaseConfig.client
          .from('ticket_tiers')
          .select()
          .eq('event_id', widget.event.id)
          .eq('is_active', true)
          .order('price', ascending: true); // Cheapest first

      final tiers = (response as List)
          .map((json) => TicketTier.fromJson(json))
          .toList();

      if (mounted) {
        setState(() {
          _tiers = tiers;
          // Auto-select first available tier if exists
          if (_tiers.isNotEmpty) {
            _selectedTier = _tiers.firstWhere(
              (t) => !t.isSoldOut,
              orElse: () => _tiers.first,
            );
          }
          _isLoadingTiers = false;
        });
      }
    } catch (e) {
      print('⚠️ Failed to fetch tiers: $e');
      if (mounted) setState(() => _isLoadingTiers = false);
    }
  }

  /// Fetch actual sold count via RPC (bypasses RLS on tickets table)
  Future<void> _fetchRealAvailability() async {
    try {
      final int actualSold = await SupabaseConfig.client.rpc(
        'get_event_sold_count',
        params: {'p_event_id': widget.event.id},
      );

      final int available = widget.event.capacity - actualSold;

      if (mounted) {
        setState(() {
          _realTicketsAvailable = available > 0 ? available : 0;
        });
      }
    } catch (e) {
      print('⚠️ Failed to fetch real availability: $e');
    }
  }

  Future<void> _checkEventDetails() async {
    // If fee info is missing, fetch full event details
    if (widget.event.passFeesToCustomer == null) {
      setState(() => _isLoadingEventDetails = true);
      try {
        final event = await EventService().getEvent(widget.event.id);
        if (mounted) {
          setState(() {
            _fullEvent = event;
            _isLoadingEventDetails = false;
          });
        }
      } catch (e) {
        print('⚠️ Failed to fetch event details: $e');
        if (mounted) setState(() => _isLoadingEventDetails = false);
      }
    } else {
      // Already has data
      setState(() => _fullEvent = widget.event);
    }
  }

  Future<void> _fetchUserProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      try {
        // Pre-fill email from Auth
        _emailController.text = user.email ?? '';

        // Fetch profile for name
        final data = await SupabaseConfig.client
            .from('users')
            .select('display_name')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            _nameController.text = data['display_name'] ?? '';
            // Phone number must be entered manually since we don't store it in users table
          });
        }
      } catch (e) {
        print('⚠️ Failed to fetch profile: $e');
      }
    }
  }

  Future<void> _applyPromoCode() async {
    final code = _promoCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isCheckingPromo = true;
      _promoError = null;
    });

    try {
      // We check promo via DB direct select first for optimistic UI updates
      // The real validation happens in the Edge Function during checkout.
      // Note: app_only=true codes are valid here — the web team blocks them
      // on their side. We intentionally do NOT filter by app_only so that
      // app-exclusive codes work correctly in the app.
      final response = await SupabaseConfig.client
          .from('promo_codes')
          .select()
          .eq('event_id', widget.event.id)
          .eq('code', code.toUpperCase()) // Force uppercase
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _promoError = 'Invalid promo code';
          _appliedPromoCode = null;
          _promoDiscountAmount = 0;
        });
      } else {
        // Calculate discount (optimistic)
        final type = response['discount_type'];
        final amount = (response['discount_amount'] as num).toDouble();

        // Basic limits check
        final usageLimit = response['usage_limit'] as int?;
        final usageCount = response['usage_count'] as int? ?? 0;
        final expiresAt = response['expires_at'] != null
            ? DateTime.parse(response['expires_at'])
            : null;

        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          throw Exception('Promo code expired');
        }
        if (usageLimit != null && usageCount >= usageLimit) {
          throw Exception('Promo usage limit reached');
        }

        double discount = 0;
        double currentPrice = _selectedTier?.price ?? widget.event.ticketPrice;
        double subtotal = currentPrice * _quantity;

        if (type == 'percentage') {
          discount = subtotal * (amount / 100);
        } else {
          discount =
              amount; // Fixed amount off total (or per ticket? usually total)
          // Actually implementation usually varies. Edge function assumes fixed amount per order
          // or we need to clarify.
          // Let's assume fixed amount off for now based on Edge Function logic `discountAmount = promo.discount_amount`.
        }

        // Cap at subtotal
        if (discount > subtotal) discount = subtotal;

        setState(() {
          _appliedPromoCode = code.toUpperCase();
          _promoDiscountAmount = discount;
          _promoError = null;
        });
      }
    } catch (e) {
      setState(() {
        _promoError = e.toString().replaceAll('Exception: ', '');
        _appliedPromoCode = null;
        _promoDiscountAmount = 0;
      });
    } finally {
      setState(() => _isCheckingPromo = false);
    }
  }

  void _removePromoCode() {
    setState(() {
      _appliedPromoCode = null;
      _promoDiscountAmount = 0;
      _promoCodeController.clear();
      _promoError = null;
    });
  }

  void _recalculatePromo() {
    if (_appliedPromoCode != null) {
      // Re-run apply to update amount based on new qty/tier
      _applyPromoCode();
    }
  }

  /// Submit a registration request (RPC). Returns the status string:
  /// 'pending' (organizer must approve) or 'auto_approved' (continue to payment).
  /// Throws on failure with a user-friendly message.
  Future<String> _submitRegistrationRequest() async {
    final isGuest = SupabaseConfig.client.auth.currentUser == null;
    try {
      final response = await SupabaseConfig.client.rpc(
        'submit_event_request',
        params: {
          'p_event_id': widget.event.id,
          'p_answers': _registrationAnswers.entries
              .map((e) => {'question_id': e.key, 'answer': e.value})
              .toList(),
          if (_selectedTier != null) 'p_tier_id': _selectedTier!.id,
          if (isGuest) ...{
            'p_guest_email': _emailController.text.trim(),
            'p_guest_name': _nameController.text.trim(),
          },
        },
      );

      final result = Map<String, dynamic>.from(response as Map);
      _registrationId = result['registration_id'] as String?;
      return (result['status'] as String?) ?? '';
    } catch (e) {
      final msg = e.toString();
      String userMsg;
      if (msg.contains('already registered')) {
        userMsg = 'You have already registered for this event.';
      } else if (msg.contains('Event not found')) {
        userMsg = 'Event not found.';
      } else if (msg.contains('not accepting')) {
        userMsg = 'This event is no longer accepting registrations.';
      } else if (msg.contains('Required questions')) {
        userMsg = 'Please answer all required questions.';
      } else if (msg.contains('guest_email')) {
        userMsg = 'Please enter your email address.';
      } else {
        userMsg = 'Could not submit your request. Please try again.';
      }
      throw Exception(userMsg);
    }
  }

  void _showRequestSubmittedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Request submitted'),
          ],
        ),
        content: const Text(
          'Your registration request has been sent to the organizer. '
          'You\'ll be notified by email and in-app when they review it.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Create purchase intent via Edge Function
  Future<Map<String, dynamic>> _createInvoice({required int quantity}) async {
    // Collect Guest/User Details
    final guestDetails = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _completePhoneNumber.isNotEmpty
          ? _completePhoneNumber
          : _phoneController.text.trim(),
    };

    final body = {
      'event_id': widget.event.id,
      'quantity': quantity,
      // 'amount' is calculated by backend now
      'guest_details': guestDetails,
      'success_url': 'https://hanghut.com/checkout/success',
      'failure_url': 'https://hanghut.com/events/${widget.event.id}',
      // NEW PARAMS
      if (_selectedTier != null) 'tier_id': _selectedTier!.id,
      if (_appliedPromoCode != null) 'promo_code': _appliedPromoCode,
      'subscribed_to_newsletter': _subscribedToNewsletter,
      if (_registrationId != null) 'registration_id': _registrationId,
      if (_subscriberDiscount?['has_discount'] == true)
        'has_subscriber_discount': true,
    };

    final response = await SupabaseConfig.client.functions.invoke(
      'create-purchase-intent',
      body: body,
    );

    if (response.status != 200) {
      try {
        final err = response.data;
        if (err is Map && err['error'] != null) {
          throw Exception(err['error']['message']);
        }
      } catch (_) {}
      throw Exception('Failed to create purchase intent: ${response.status}');
    }

    return response.data as Map<String, dynamic>;
  }

  /// Main purchase flow
  Future<void> _proceedToPayment() async {
    if (_isLoading) return;

    // Validate Form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate registration questions
    final questionError = RegistrationQuestionsForm.validate(
      _registrationQuestions,
      _registrationAnswers,
    );
    if (questionError != null) {
      _showErrorDialog('Registration Required', questionError);
      return;
    }

    // Validate Tier
    if (_tiers.isNotEmpty && _selectedTier == null) {
      _showErrorDialog('Select Ticket', 'Please select a ticket type.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // If event has registration questions OR requires approval, submit the
      // request first. This creates the event_registrations row + answers,
      // and gates payment behind organizer approval when required.
      final needsRegistration =
          _registrationQuestions.isNotEmpty || widget.event.requireApproval;
      if (needsRegistration && _registrationId == null) {
        final status = await _submitRegistrationRequest();
        if (status == 'pending') {
          if (mounted) {
            setState(() => _isLoading = false);
            _showRequestSubmittedDialog();
          }
          return;
        }
        // auto_approved → fall through to payment
      }

      // Create new invoice with current form data
      final invoice = await _createInvoice(quantity: _quantity);

      // Extract data from nested response structure
      final data = invoice['data'] as Map<String, dynamic>;
      _currentPurchaseIntentId = data['intent_id'] as String;

      // FREE TICKETS — backend marks as paid immediately, no Xendit
      if (data['free'] == true) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TicketSuccessScreen(
                purchaseIntentId: _currentPurchaseIntentId!,
              ),
            ),
          );
        }
        return;
      }

      final invoiceUrl = data['payment_url'] as String;

      // Validate URL
      if (!invoiceUrl.startsWith('https://')) {
        throw Exception('Invalid payment URL');
      }

      // Launch payment page in Custom Tabs / SFSafariViewController
      final launched = await launchUrl(
        Uri.parse(invoiceUrl),
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );

      if (!launched) {
        throw Exception('Could not open payment page');
      }

      // Start background polling for payment status
      if (mounted) {
        _startPaymentPolling();
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        String displayMsg = errorMsg;
        if (errorMsg.toLowerCase().contains('not enough tickets') ||
            errorMsg.toLowerCase().contains('sold out')) {
          displayMsg =
              'Sorry, there are not enough tickets available for this selection.';
        } else if (errorMsg.toLowerCase().contains('purchase limits')) {
          displayMsg =
              'You have exceeded the maximum number of tickets allowed per person.';
        }
        _showErrorDialog('Booking Failed', displayMsg);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ... _startPaymentPolling and others remain same ...
  // Re-pasting for completeness since I stripped the whole file structure in replace attempt

  void _startPaymentPolling() {
    _isPaymentInProgress = true;
    PushNotificationService.suppressNotifications = true;
    _consecutiveErrors = 0;

    // GEOFENCING DISABLED for Android review — uncomment to re-enable
    // Workmanager().cancelByUniqueName('geofence-check');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProcessingDialog(
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    ).then((_) {
      _pollingTimer?.cancel();
      _isPaymentInProgress = false;
    });

    // Start the polling timer (shared logic with resume)
    _restartPolling();
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Taking Longer Than Expected'),
        content: const Text(
          'The payment is taking longer than usual. '
          'You can check "My Tickets" in a few minutes or contact support.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/my-tickets');
            },
            child: const Text('Check My Tickets'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = _fullEvent ?? widget.event;

    // Fee Logic (Match Backend)
    double baseUnitPrice = _selectedTier?.price ?? event.ticketPrice;
    final bool isFree = baseUnitPrice == 0;

    double feeAmount = 0;
    if (event.passFeesToCustomer == true && !isFree) {
      feeAmount = event.fixedFeePerTicket ?? 15.00;
    }
    double displayUnitPrice = baseUnitPrice + feeAmount;
    double displaySubtotal = displayUnitPrice * _quantity;

    // Subscriber discount (server-verified — flag sent to edge function)
    double subscriberDiscountAmount = 0;
    final hasSubscriberDiscount = _subscriberDiscount?['has_discount'] == true;
    if (hasSubscriberDiscount && !isFree) {
      final discountedBase =
          (_subscriberDiscount!['discounted_price'] as num).toDouble();
      subscriberDiscountAmount = (baseUnitPrice - discountedBase) * _quantity;
    }

    double displayDiscount = _promoDiscountAmount + subscriberDiscountAmount;
    double total = displaySubtotal - displayDiscount;
    if (total < 0) total = 0;

    // Early access + subscriber-only gate
    final earlyAccessHours = event.subscriberEarlyAccessHours;
    DateTime? publicSaleOpens;
    bool isEarlyAccessBlocked = false;
    if (earlyAccessHours != null) {
      publicSaleOpens =
          event.startDatetime.subtract(Duration(hours: earlyAccessHours));
      isEarlyAccessBlocked =
          DateTime.now().isBefore(publicSaleOpens) && !_isActiveSubscriber;
    }
    final isSubOnlyBlocked = event.isSubscriberOnly && !_isActiveSubscriber;

    final primary = AppTheme.primaryColor;
    final isGated = isSubOnlyBlocked || isEarlyAccessBlocked;

    // ── GATED STATE: no steps, just show why purchase is blocked ──
    if (isGated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy Tickets'), centerTitle: true),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventSummaryCard(event: widget.event),
              const SizedBox(height: 24),
              if (isSubOnlyBlocked)
                _SubscriberGateBanner(
                  message: 'This event is for members only.',
                  subMessage: 'Subscribe to get access.',
                  icon: Icons.lock_rounded,
                )
              else if (publicSaleOpens != null)
                _SubscriberGateBanner(
                  message: 'Members get early access',
                  subMessage:
                      'Public sale opens ${DateFormat('MMM d \'at\' h:mm a').format(publicSaleOpens)}',
                  icon: Icons.bolt_rounded,
                ),
            ],
          ),
        ),
      );
    }

    // ── STEP DEFINITIONS (Questions step only when the event has them) ──
    final hasQuestions = _registrationQuestions.isNotEmpty;
    final stepTitles = <String>[
      'Ticket',
      'Details',
      if (hasQuestions) 'Questions',
      'Review',
    ];
    final lastStep = stepTitles.length - 1;
    final step = _currentStep.clamp(0, lastStep);
    final isLast = step == lastStep;

    final stepBodies = <Widget>[
      _buildTicketStep(feeAmount),
      _buildDetailsStep(),
      if (hasQuestions) _buildQuestionsStep(),
      _buildReviewStep(
        displayUnitPrice: displayUnitPrice,
        displaySubtotal: displaySubtotal,
        subscriberDiscountAmount: subscriberDiscountAmount,
        total: total,
      ),
    ];

    final payLabel = (widget.event.requireApproval &&
            widget.existingRegistrationId == null)
        ? 'Submit Request'
        : (total <= 0
            ? 'Get Free Tickets'
            : 'Pay Now • ₱${total.toStringAsFixed(2)}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy Tickets'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (step > 0) {
              setState(() => _currentStep = step - 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _StepProgressBar(titles: stepTitles, current: step),
            Expanded(
              child: IndexedStack(
                index: step,
                sizing: StackFit.expand,
                children: stepBodies
                    .map((body) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [body],
                          ),
                        ))
                    .toList(),
              ),
            ),

            // Sticky bottom navigation
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    if (step > 0) ...[
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() => _currentStep = step - 1),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(
                                color: primary.withOpacity(0.4), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: const Text('Back',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : (isLast
                                  ? _proceedToPayment
                                  : () => _advanceStep(stepTitles)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isLast ? payLabel : 'Continue',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step navigation + per-step validation ──────────────────────────────────
  void _advanceStep(List<String> titles) {
    final current = titles[_currentStep];
    if (current == 'Ticket') {
      if (_tiers.isNotEmpty && _selectedTier == null) {
        _snack('Please select a ticket type.');
        return;
      }
    } else if (current == 'Details') {
      if (!(_formKey.currentState?.validate() ?? false)) return;
    } else if (current == 'Questions') {
      final err = RegistrationQuestionsForm.validate(
        _registrationQuestions,
        _registrationAnswers,
      );
      if (err != null) {
        _snack(err);
        return;
      }
    }
    setState(() => _currentStep = _currentStep + 1);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shared modern filled input style for all checkout text fields.
  InputDecoration _modernInput(String label, {IconData? icon, String? hint}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;
    final labelColor = isDark ? Colors.white70 : Colors.grey[700];
    return InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hint,
      counterText: '', // hide the phone-field length counter ("0/10")
      labelStyle: TextStyle(color: labelColor),
      floatingLabelStyle: const TextStyle(color: AppTheme.primaryColor),
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: isDark ? Colors.white54 : Colors.grey[600])
          : null,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 13.5, color: Colors.grey[600])),
        ],
      ],
    );
  }

  // ── STEP 1: Ticket type + quantity ──
  Widget _buildTicketStep(double feeAmount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EventSummaryCard(event: widget.event),
        const SizedBox(height: 28),
        if (_isLoadingTiers)
          const Center(child: CircularProgressIndicator())
        else if (_tiers.isNotEmpty) ...[
          _sectionTitle('Select Ticket Type'),
          const SizedBox(height: 14),
          ..._tiers.map(
            (tier) => _TierOption(
              tier: tier,
              feeAmount: feeAmount,
              isSelected: _selectedTier?.id == tier.id,
              onTap: () {
                if (!tier.isSoldOut) {
                  setState(() {
                    _selectedTier = tier;
                    _recalculatePromo();
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 28),
        ],
        _sectionTitle('Quantity'),
        const SizedBox(height: 14),
        _QuantitySelector(
          quantity: _quantity,
          max: (_selectedTier != null)
              ? _selectedTier!.quantityAvailable.clamp(1, 10)
              : _realTicketsAvailable.clamp(1, 10),
          onChanged: (qty) => setState(() {
            _quantity = qty;
            _recalculatePromo();
          }),
        ),
      ],
    );
  }

  // ── STEP 2: Contact details ──
  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Your Details',
            subtitle: 'Where should we send your tickets?'),
        const SizedBox(height: 18),
        TextFormField(
          controller: _nameController,
          decoration: _modernInput('Full Name', icon: Icons.person_outline),
          validator: (value) =>
              value == null || value.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _modernInput('Email Address', icon: Icons.email_outlined),
          validator: (value) => value == null
              ? 'Required'
              : (!value.contains('@') ? 'Invalid email' : null),
        ),
        const SizedBox(height: 14),
        IntlPhoneField(
          controller: _phoneController,
          decoration: _modernInput('Phone Number'),
          initialCountryCode: 'PH',
          dropdownIconPosition: IconPosition.trailing,
          flagsButtonPadding: const EdgeInsets.only(left: 8),
          dropdownTextStyle: const TextStyle(fontSize: 16),
          pickerDialogStyle: PickerDialogStyle(
            backgroundColor: Colors.white,
            countryCodeStyle: const TextStyle(color: Colors.black54),
            countryNameStyle: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
            ),
            searchFieldInputDecoration: InputDecoration(
              hintText: 'Search country',
              hintStyle: const TextStyle(color: Colors.black38),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          onChanged: (phone) {
            _completePhoneNumber = phone.completeNumber;
          },
        ),
      ],
    );
  }

  // ── STEP 3: Registration questions ──
  Widget _buildQuestionsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('A Few Questions',
            subtitle: 'The organizer needs this to confirm your spot.'),
        const SizedBox(height: 18),
        RegistrationQuestionsForm(
          questions: _registrationQuestions,
          answers: _registrationAnswers,
          onChanged: (updated) =>
              setState(() => _registrationAnswers = updated),
        ),
      ],
    );
  }

  // ── STEP 4: Review, promo, newsletter, price breakdown ──
  Widget _buildReviewStep({
    required double displayUnitPrice,
    required double displaySubtotal,
    required double subscriberDiscountAmount,
    required double total,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Review & Pay'),
        const SizedBox(height: 20),

        // Promo code
        const Text('Promo Code',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promoCodeController,
                textCapitalization: TextCapitalization.characters,
                enabled: _appliedPromoCode == null,
                decoration: _modernInput('', hint: 'ENTER CODE').copyWith(
                  labelText: null,
                  errorText: _promoError,
                  suffixIcon: _appliedPromoCode != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _removePromoCode,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_isCheckingPromo || _appliedPromoCode != null)
                  ? null
                  : _applyPromoCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(88, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: _isCheckingPromo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Apply'),
            ),
          ],
        ),
        if (_appliedPromoCode != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Code $_appliedPromoCode applied!',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        const SizedBox(height: 20),

        // Newsletter opt-in
        CheckboxListTile(
          value: _subscribedToNewsletter,
          onChanged: (val) =>
              setState(() => _subscribedToNewsletter = val ?? true),
          title: const Text(
            'Subscribe to updates from this organizer',
            style: TextStyle(fontSize: 14),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: AppTheme.primaryColor,
        ),

        const SizedBox(height: 16),

        if (_isLoadingEventDetails)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: LinearProgressIndicator(),
          ),

        _PriceBreakdown(
          unitPrice: displayUnitPrice,
          quantity: _quantity,
          subtotal: displaySubtotal,
          promoDiscount: _promoDiscountAmount,
          subscriberDiscount: subscriberDiscountAmount,
          total: total,
        ),
      ],
    );
  }
}

// ============================================
// SUPPORTING WIDGETS
// ============================================

/// Segmented progress bar with step labels for the multi-step checkout.
class _StepProgressBar extends StatelessWidget {
  final List<String> titles;
  final int current;

  const _StepProgressBar({required this.titles, required this.current});

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < titles.length; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? primary
                          : primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (i != titles.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${current + 1} of ${titles.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
              Text(
                titles[current],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierOption extends StatelessWidget {
  final TicketTier tier;
  final double feeAmount;
  final bool isSelected;
  final VoidCallback onTap;

  const _TierOption({
    required this.tier,
    this.feeAmount = 0,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final price = tier.price + feeAmount;
    final baseColor =
        isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade300;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? primary.withValues(alpha: 0.12) : baseColor,
        border: Border.all(
          color: isSelected ? primary : borderColor,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Selection indicator
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? primary : Colors.grey.shade400,
                      width: isSelected ? 6.5 : 1.6,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (tier.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          tier.description!,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12.5),
                        ),
                      ],
                      if (tier.isSoldOut) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SOLD OUT',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  price <= 0 ? 'Free' : '₱${price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: isSelected
                        ? primary
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventSummaryCard extends StatelessWidget {
  final Event event;

  const _EventSummaryCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.0 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event image gallery
          _EventImageGallery(event: event),

          // Event details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.location_on, text: event.venueName),
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.calendar_today,
                  text: DateFormat(
                    'MMM d, y • h:mm a',
                  ).format(event.startDatetime),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  const _QuantitySelector({
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // If sold out or max is 0
    if (max <= 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('Unavailable', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final primary = AppTheme.primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _stepButton(
                icon: Icons.remove_rounded,
                enabled: quantity > 1,
                onTap: () => onChanged(quantity - 1),
                primary: primary,
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _stepButton(
                icon: Icons.add_rounded,
                enabled: quantity < max,
                onTap: () => onChanged(quantity + 1),
                primary: primary,
              ),
            ],
          ),
        ),
        const Spacer(),
        if (max < 10)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Only $max left',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.orange[800],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required Color primary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? primary : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  final double unitPrice;
  final int quantity;
  final double subtotal;
  final double promoDiscount;
  final double subscriberDiscount;
  final double total;

  const _PriceBreakdown({
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    this.promoDiscount = 0,
    this.subscriberDiscount = 0,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          _PriceRow(
            label: 'Ticket Price',
            value: '₱${unitPrice.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _PriceRow(label: 'Quantity', value: '× $quantity'),
          if (subscriberDiscount > 0) ...[
            const SizedBox(height: 8),
            _PriceRow(
              label: '👑 Member discount',
              value: '-₱${subscriberDiscount.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          ],
          if (promoDiscount > 0) ...[
            const SizedBox(height: 8),
            _PriceRow(
              label: 'Promo code',
              value: '-₱${promoDiscount.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: DottedLikeDivider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                total <= 0 ? 'Free' : '₱${total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: primary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A thin dashed divider used inside the price card.
class DottedLikeDivider extends StatelessWidget {
  const DottedLikeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dashColor =
        isDark ? Colors.white.withValues(alpha: 0.18) : Colors.grey.shade300;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const dashSpace = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashWidth,
              height: 1.4,
              color: dashColor,
            ),
          ),
        );
      },
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _PriceRow({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white60 : Colors.grey[700];
    final valueColor = isDark ? Colors.white : Colors.black87;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            color: color ?? labelColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            color: color ?? valueColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProcessingDialog extends StatelessWidget {
  final VoidCallback onCancel;

  const _ProcessingDialog({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.deepPurple),
          const SizedBox(height: 24),
          const Text(
            'Waiting for Payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'We are waiting for Xendit to confirm your payment. This usually takes a few seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Cancel & Go Back',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventImageGallery extends StatefulWidget {
  final Event event;
  const _EventImageGallery({required this.event});

  @override
  State<_EventImageGallery> createState() => _EventImageGalleryState();
}

class _EventImageGalleryState extends State<_EventImageGallery> {
  int _current = 0;
  late final PageController _pageController;
  late final List<String> _allImages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final cover = widget.event.coverImageUrl;
    final extras = widget.event.imageUrls;
    final seen = <String>{};
    _allImages = [
      if (cover != null && cover.isNotEmpty) cover,
      ...extras.where((u) => u != cover),
    ].where((u) => seen.add(u)).toList();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullscreen(int startIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenGallery(images: _allImages, initialIndex: startIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? Colors.white12 : Colors.grey[300];
    if (_allImages.isEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: placeholderColor,
            child: Icon(Icons.event,
                size: 48, color: isDark ? Colors.white38 : Colors.grey[600]),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _allImages.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openFullscreen(i),
                // White backdrop so transparent (logo) images render correctly
                // in dark mode instead of showing the dark card through them.
                child: Container(
                  color: Colors.white,
                  child: CachedNetworkImage(
                    imageUrl: _allImages[i],
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey[300]),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 48),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_allImages.length > 1)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_current + 1} / ${_allImages.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _openFullscreen(_current),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
          if (_allImages.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _allImages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _current == i ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _current == i ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _FullscreenGallery({required this.images, required this.initialIndex});

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_current + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.images[i],
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const CircularProgressIndicator(color: Colors.white),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriberGateBanner extends StatelessWidget {
  final String message;
  final String subMessage;
  final IconData icon;

  const _SubscriberGateBanner({
    required this.message,
    required this.subMessage,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFFFFD700)),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subMessage,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
