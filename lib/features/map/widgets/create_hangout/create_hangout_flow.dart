import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/home/widgets/location_picker_modal.dart';

import 'hangout_progress_bar.dart';
import 'step_what_where.dart';
import 'step_when_vibes.dart';
import 'step_who_invited.dart';
import 'step_review.dart';

/// Full-screen multi-step wizard for creating a hangout.
class CreateHangoutFlow extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;
  final VoidCallback onTableCreated;
  final String? groupId;
  final String? groupName;

  const CreateHangoutFlow({
    super.key,
    this.currentLat,
    this.currentLng,
    required this.onTableCreated,
    this.groupId,
    this.groupName,
  });

  @override
  State<CreateHangoutFlow> createState() => CreateHangoutFlowState();
}

class CreateHangoutFlowState extends State<CreateHangoutFlow>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 4;

  // ─── Shared form state ───────────────────────────────
  final activityController = TextEditingController();
  final venueController = TextEditingController();
  final descriptionController = TextEditingController();
  final inviteController = TextEditingController();

  final _tableService = TableService();
  final _imagePicker = ImagePicker();

  // User
  String? userName;

  // Venue
  String? venueName;
  String? venueAddress;
  double? venueLat;
  double? venueLng;

  // When
  late DateTime selectedDateTime;

  // Vibes
  String? selectedGifUrl;
  File? markerImage;
  String? selectedEmoji = '📍';

  // Who
  double maxCapacity = 4;
  String budgetRange = 'medium';
  String goalType = 'friends';
  bool requiresApproval = false;
  late String visibility;

  // Advanced filters
  String genderFilter = 'everyone';
  bool ageFilterEnabled = false;
  RangeValues ageRange = const RangeValues(18, 65);
  String enforcement = 'soft';

  // Invite
  List<Map<String, dynamic>> inviteSearchResults = [];
  List<Map<String, dynamic>> invitedUsers = [];
  Timer? _inviteDebounce;
  bool showInviteResults = false;

  // Places
  List<Map<String, dynamic>> placePredictions = [];
  Timer? _debounce;
  bool showPredictions = false;

  // Loading / animations
  bool _isLoading = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Google Places key
  static const String _fallbackGoogleKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';
  String get googleApiKey {
    final envKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    return envKey.isNotEmpty ? envKey : _fallbackGoogleKey;
  }

  @override
  void initState() {
    super.initState();
    visibility = widget.groupId != null ? 'group_only' : 'public';
    _loadUserProfile();
    venueController.addListener(_onSearchChanged);

    final now = DateTime.now().add(const Duration(minutes: 60));
    selectedDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute >= 30 ? 30 : 0,
    );

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
    _pageController.dispose();
    activityController.dispose();
    venueController.dispose();
    descriptionController.dispose();
    inviteController.dispose();
    _debounce?.cancel();
    _inviteDebounce?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  /// Public rebuild trigger for child step widgets.
  void rebuild() => setState(() {});

  // ─── Navigation ─────────────────────────────────────

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return activityController.text.trim().isNotEmpty;
      case 1:
        return true; // date/time has defaults
      case 2:
        return true; // all optional
      case 3:
        return true; // review
      default:
        return false;
    }
  }

  void _nextStep() {
    if (!_canProceed()) {
      HapticFeedback.mediumImpact();
      _shakeController.forward(from: 0);
      return;
    }

    HapticFeedback.lightImpact();

    if (_currentStep == _totalSteps - 1) {
      _createTable();
      return;
    }

    setState(() => _currentStep++);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _prevStep() {
    HapticFeedback.lightImpact();
    if (_currentStep == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _currentStep--);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── User profile ──────────────────────────────────

  Future<void> _loadUserProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      final response = await SupabaseConfig.client
          .from('users')
          .select('display_name')
          .eq('id', user.id)
          .single();
      if (mounted) setState(() => userName = response['display_name']);
    }
  }

  // ─── Venue / Places ────────────────────────────────

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (venueController.text.isNotEmpty && venueName == null) {
        _getPlacePredictions(venueController.text);
      } else {
        setState(() {
          placePredictions = [];
          showPredictions = false;
        });
      }
    });
  }

  Future<void> _getPlacePredictions(String input) async {
    try {
      var urlString =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$googleApiKey';
      if (widget.currentLat != null && widget.currentLng != null) {
        urlString +=
            '&location=${widget.currentLat},${widget.currentLng}&radius=30000';
      }
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            placePredictions = List<Map<String, dynamic>>.from(
              data['predictions'].map(
                (p) => {
                  'place_id': p['place_id'],
                  'description': p['description'],
                  'main_text': p['structured_formatting']['main_text'],
                  'secondary_text':
                      p['structured_formatting']['secondary_text'],
                },
              ),
            );
            showPredictions = true;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Places Error: $e');
    }
  }

  void selectPlace(String placeId, String description) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleApiKey&fields=geometry,name,formatted_address',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];
          setState(() {
            venueName = result['name'];
            venueAddress = result['formatted_address'];
            venueLat = location['lat'];
            venueLng = location['lng'];
            venueController.text = venueName!;
            showPredictions = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Place Details Error: $e');
    }
  }

  void clearVenueSelection() {
    setState(() {
      venueName = null;
      venueLat = null;
      venueLng = null;
    });
  }

  Future<void> pickLocationOnMap() async {
    Position? currentPosition;
    if (widget.currentLat != null && widget.currentLng != null) {
      currentPosition = Position(
        longitude: widget.currentLng!,
        latitude: widget.currentLat!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerModal(initialPosition: currentPosition),
      ),
    );
    if (result != null && result is Map) {
      final address = result['address'] as String?;
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;
      if (lat != null && lng != null) {
        setState(() {
          venueAddress = address;
          venueLat = lat;
          venueLng = lng;
          venueName = address;
          venueController.text = address ?? '';
          showPredictions = false;
        });
      }
    }
  }

  // ─── Date / Time ───────────────────────────────────

  Future<void> pickDate() async {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) => Theme(
        data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.primaryColor,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          selectedDateTime.hour,
          selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> pickTime() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      builder: (context, child) => Theme(
        data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.primaryColor,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDateTime = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  // ─── Marker ────────────────────────────────────────

  Future<void> pickMarkerImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) setState(() => markerImage = File(image.path));
  }

  void selectEmoji(String emoji) => setState(() => selectedEmoji = emoji);

  void showFullEmojiPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 400,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            setState(() => selectedEmoji = emoji.emoji);
            Navigator.pop(context);
          },
          config: Config(
            height: 256,
            checkPlatformCompatibility: true,
            viewOrderConfig: const ViewOrderConfig(),
            emojiViewConfig: EmojiViewConfig(
              emojiSizeMax:
                  28 *
                  (foundation.defaultTargetPlatform == TargetPlatform.iOS
                      ? 1.20
                      : 1.0),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              columns: 7,
            ),
            skinToneConfig: const SkinToneConfig(),
            categoryViewConfig: CategoryViewConfig(
              indicatorColor: AppTheme.primaryColor,
              iconColorSelected: AppTheme.primaryColor,
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            ),
            bottomActionBarConfig: BottomActionBarConfig(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              buttonColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              buttonIconColor: Colors.grey,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Invite ────────────────────────────────────────

  void onInviteSearchChanged(String query) {
    if (_inviteDebounce?.isActive ?? false) _inviteDebounce!.cancel();
    _inviteDebounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _searchUsersForInvite(query.trim());
      } else {
        setState(() {
          inviteSearchResults = [];
          showInviteResults = false;
        });
      }
    });
  }

  Future<void> _searchUsersForInvite(String query) async {
    try {
      final cleanQuery = query.startsWith('@') ? query.substring(1) : query;
      if (cleanQuery.isEmpty) return;
      final results = await SocialService().searchUsers(cleanQuery, limit: 5);
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      final filtered = results.where((u) {
        final uid = u['id'] as String;
        return uid != currentUserId &&
            !invitedUsers.any((inv) => inv['id'] == uid);
      }).toList();
      if (mounted) {
        setState(() {
          inviteSearchResults = filtered;
          showInviteResults = filtered.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('❌ Invite search error: $e');
    }
  }

  void addInvitedUser(Map<String, dynamic> user) {
    setState(() {
      invitedUsers.add(user);
      inviteSearchResults = [];
      showInviteResults = false;
      inviteController.clear();
    });
  }

  void removeInvitedUser(int index) {
    setState(() => invitedUsers.removeAt(index));
  }

  // ─── Filters ───────────────────────────────────────

  Map<String, dynamic>? _buildFiltersJson() {
    if (genderFilter == 'everyone' && !ageFilterEnabled) return null;
    final filters = <String, dynamic>{};
    if (genderFilter != 'everyone') filters['gender'] = genderFilter;
    if (ageFilterEnabled) {
      filters['age_min'] = ageRange.start.round();
      filters['age_max'] = ageRange.end.round();
    }
    filters['enforcement'] = enforcement;
    return filters;
  }

  // ─── Create ────────────────────────────────────────

  Future<void> _createTable() async {
    if (activityController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final activity = activityController.text.trim();
      final hostLabel = widget.groupName ?? userName ?? 'Someone';
      final title = '$hostLabel wants to $activity';
      final description = descriptionController.text.trim();

      await _tableService.createTable(
        latitude: venueLat ?? widget.currentLat ?? 0,
        longitude: venueLng ?? widget.currentLng ?? 0,
        scheduledTime: selectedDateTime,
        activityType: 'other',
        venueName: venueName ?? 'TBD',
        venueAddress: venueAddress ?? '',
        title: title,
        description: description.isNotEmpty ? description : null,
        maxCapacity: maxCapacity.round(),
        budgetMin: budgetRange == 'low' ? 0 : (budgetRange == 'high' ? 50 : 20),
        budgetMax: budgetRange == 'low'
            ? 20
            : (budgetRange == 'high' ? 100 : 50),
        requiresApproval: requiresApproval,
        goalType: goalType,
        imageUrl: selectedGifUrl,
        markerImage: markerImage,
        markerEmoji: markerImage == null ? (selectedEmoji ?? '📍') : null,
        visibility: visibility,
        filters: _buildFiltersJson(),
        invitedUserIds: invitedUsers.isNotEmpty
            ? invitedUsers.map((u) => u['id'] as String).toList()
            : null,
        groupId: widget.groupId,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onTableCreated();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Hangout created! 🎉')));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to create hangout. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── UI ────────────────────────────────────────────

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'What & Where';
      case 1:
        return 'When & Vibes';
      case 2:
        return "Who's Invited";
      case 3:
        return 'Review';
      default:
        return '';
    }
  }

  String get _nextLabel {
    if (_currentStep == _totalSteps - 1) return 'Create Hangout';
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
                      _currentStep == 0 ? Icons.close : Icons.arrow_back,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: _prevStep,
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
                        key: ValueKey(_currentStep),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance the back button
                ],
              ),
            ),

            // ── Progress bar ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: HangoutProgressBar(
                currentStep: _currentStep,
                totalSteps: _totalSteps,
              ),
            ),

            // ── Pages ───────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StepWhatWhere(flow: this),
                  StepWhenVibes(flow: this),
                  StepWhoInvited(flow: this),
                  StepReview(flow: this),
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
                      key: ValueKey('btn_$_currentStep'),
                      onPressed: _isLoading ? null : _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canProceed()
                            ? AppTheme.primaryColor
                            : (isDark ? Colors.grey[800] : Colors.grey[300]),
                        foregroundColor: _canProceed()
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
                      child: _isLoading
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
                                if (_currentStep < _totalSteps - 1) ...[
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
