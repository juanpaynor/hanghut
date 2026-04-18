import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/trip_service.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/map/widgets/create_hangout/hangout_progress_bar.dart';

import 'trip_step_where_when.dart';
import 'trip_step_style_interests.dart';
import 'trip_step_goals.dart';
import 'trip_step_review.dart';

/// Full-screen multi-step wizard for planning a trip.
class CreateTripFlow extends StatefulWidget {
  final VoidCallback onTripCreated;

  const CreateTripFlow({super.key, required this.onTripCreated});

  @override
  State<CreateTripFlow> createState() => CreateTripFlowState();
}

class CreateTripFlowState extends State<CreateTripFlow>
    with TickerProviderStateMixin {
  final pageController = PageController();
  int currentStep = 0;
  static const totalSteps = 4;

  // ─── Shared form state ───────────────────────────────
  final cityController = TextEditingController();
  final countryController = TextEditingController();
  final descriptionController = TextEditingController();

  DateTime? startDate;
  DateTime? endDate;
  String travelStyle = 'moderate';
  List<String> selectedInterests = [];
  List<String> selectedGoals = [];
  bool isLoading = false;

  // ─── Data ────────────────────────────────────────────

  final List<Map<String, dynamic>> travelStyles = [
    {
      'value': 'budget',
      'label': '💰 Budget',
      'description': 'Hostels, street food',
      'icon': Icons.savings_rounded,
    },
    {
      'value': 'moderate',
      'label': '🎯 Moderate',
      'description': 'Mix of comfort & value',
      'icon': Icons.balance_rounded,
    },
    {
      'value': 'luxury',
      'label': '✨ Luxury',
      'description': 'Premium experiences',
      'icon': Icons.diamond_rounded,
    },
  ];

  final List<Map<String, String>> interests = [
    {'value': 'food', 'label': '🍜 Food & Dining'},
    {'value': 'nightlife', 'label': '🌃 Nightlife'},
    {'value': 'culture', 'label': '🏛️ Culture & History'},
    {'value': 'adventure', 'label': '🏔️ Adventure'},
    {'value': 'relaxation', 'label': '🧘 Relaxation'},
    {'value': 'shopping', 'label': '🛍️ Shopping'},
    {'value': 'photography', 'label': '📸 Photography'},
    {'value': 'nature', 'label': '🌿 Nature'},
  ];

  final List<Map<String, String>> goals = [
    {'value': 'make_friends', 'label': '👋 Make new friends'},
    {'value': 'find_companion', 'label': '🧳 Find travel companion'},
    {'value': 'local_tips', 'label': '📍 Get local tips'},
    {'value': 'group_activities', 'label': '🎉 Join group activities'},
  ];

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    pageController.dispose();
    cityController.dispose();
    countryController.dispose();
    descriptionController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  /// Public rebuild trigger for child step widgets.
  void rebuild() => setState(() {});

  // ─── Navigation ─────────────────────────────────────

  bool canProceed() {
    switch (currentStep) {
      case 0:
        return cityController.text.trim().isNotEmpty &&
            startDate != null &&
            endDate != null;
      case 1:
        return true; // travel style has default
      case 2:
        return selectedInterests.isNotEmpty && selectedGoals.isNotEmpty;
      case 3:
        return true; // review
      default:
        return false;
    }
  }

  void nextStep() {
    if (!canProceed()) {
      HapticFeedback.mediumImpact();
      _shakeController.forward(from: 0);
      return;
    }

    HapticFeedback.lightImpact();

    if (currentStep == totalSteps - 1) {
      _createTrip();
      return;
    }

    setState(() => currentStep++);
    pageController.animateToPage(
      currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void prevStep() {
    HapticFeedback.lightImpact();
    if (currentStep == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => currentStep--);
    pageController.animateToPage(
      currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── Date Picker ────────────────────────────────────

  Future<void> selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.primaryColor,
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  // ─── Create ─────────────────────────────────────────

  Future<void> _createTrip() async {
    FocusScope.of(context).unfocus();
    setState(() => isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final tripService = TripService();
      await tripService.createTrip({
        'user_id': user.id,
        'destination_city': cityController.text.trim().split(',').first,
        'destination_country': countryController.text.isNotEmpty
            ? countryController.text.trim()
            : cityController.text.trim().split(',').last.trim(),
        'start_date': startDate!.toIso8601String().split('T')[0],
        'end_date': endDate!.toIso8601String().split('T')[0],
        'travel_style': travelStyle,
        'interests': selectedInterests,
        'goals': selectedGoals,
        'description': descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        'status': 'upcoming',
      });

      final destination = cityController.text.trim().split(',').first;
      AnalyticsService().logCreateTrip(destination);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Trip planned! 🎉')));
        widget.onTripCreated();
      }
    } catch (e) {
      debugPrint('Error creating trip: $e');
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to create trip. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─── UI ─────────────────────────────────────────────

  String get _stepTitle {
    switch (currentStep) {
      case 0:
        return 'Where & When';
      case 1:
        return 'Travel Style';
      case 2:
        return 'Interests & Goals';
      case 3:
        return 'Review';
      default:
        return '';
    }
  }

  String get _nextLabel {
    if (currentStep == totalSteps - 1) return 'Plan Trip';
    return 'Next';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      currentStep == 0 ? Icons.close : Icons.arrow_back,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: prevStep,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _stepTitle,
                        key: ValueKey(currentStep),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Progress bar ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: HangoutProgressBar(
                currentStep: currentStep,
                totalSteps: totalSteps,
              ),
            ),

            // ── Pages ───────────────────────────
            Expanded(
              child: PageView(
                controller: pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  TripStepWhereWhen(flow: this),
                  TripStepStyleInterests(flow: this),
                  TripStepGoals(flow: this),
                  TripStepReview(flow: this),
                ],
              ),
            ),

            // ── Bottom bar ──────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPad),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.grey[200]!,
                  ),
                ),
              ),
              child: AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: ElevatedButton(
                      key: ValueKey('btn_$currentStep'),
                      onPressed: isLoading ? null : nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canProceed()
                            ? AppTheme.primaryColor
                            : (isDark ? Colors.grey[800] : Colors.grey[300]),
                        foregroundColor: canProceed()
                            ? Colors.white
                            : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        disabledBackgroundColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[300],
                        disabledForegroundColor: isDark
                            ? Colors.grey[500]
                            : Colors.grey[600],
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _nextLabel,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (currentStep < totalSteps - 1) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
