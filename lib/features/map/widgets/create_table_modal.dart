import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/core/services/tenor_service.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/home/widgets/location_picker_modal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;

class CreateTableModal extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;
  final VoidCallback onTableCreated;
  final String? groupId;
  final String? groupName;

  const CreateTableModal({
    super.key,
    this.currentLat,
    this.currentLng,
    required this.onTableCreated,
    this.groupId,
    this.groupName,
  });

  @override
  State<CreateTableModal> createState() => _CreateTableModalState();
}

class _CreateTableModalState extends State<CreateTableModal> {
  final _activityController = TextEditingController();
  final _venueController = TextEditingController();
  final _descriptionController = TextEditingController(); // NEW: Description
  final _tableService = TableService();
  final _imagePicker = ImagePicker();

  // User Profile
  String? _userName;

  // Form State
  String? _venueName;
  String? _venueAddress;
  double? _venueLat;
  double? _venueLng;
  DateTime _selectedDateTime = DateTime.now().add(
    const Duration(minutes: 60),
  ); // Default 1 hour from now
  double _maxCapacity = 4;
  String _budgetRange = 'medium';
  String _goalType = 'friends';
  bool _requiresApproval = false;
  bool _isLoading = false;

  // Visibility
  late String _visibility;

  // Advanced Filters
  bool _showAdvancedFilters = false;
  String _genderFilter = 'everyone'; // 'everyone', 'women_only', 'men_only', 'nonbinary_only'
  bool _ageFilterEnabled = false;
  RangeValues _ageRange = const RangeValues(18, 65);
  String _enforcement = 'soft'; // 'soft' or 'hard'

  // Invite by Handle
  final _inviteController = TextEditingController();
  List<Map<String, dynamic>> _inviteSearchResults = [];
  List<Map<String, dynamic>> _invitedUsers = [];
  Timer? _inviteDebounce;
  bool _showInviteResults = false;

  // Visuals
  String? _selectedGifUrl;
  bool _showGifPicker = false;
  File? _markerImage;
  String? _selectedEmoji = '📍'; // Default emoji

  // Curated Emojis for Grid
  final List<String> _commonEmojis = [
    '📍',
    '☕️',
    '🍺',
    '🍔',
    '🍕',
    '🍣',
    '🏀',
    '🎾',
    '🎬',
    '🎮',
    '🎤',
    '🏋️',
    '📚',
    '💻',
    '🎉',
  ];

  // Google Places
  List<Map<String, dynamic>> _placePredictions = [];
  Timer? _debounce;
  bool _showPredictions = false;
  // IMPORTANT: Replace with your actual Google Places API key!
  static const String _fallbackGoogleKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';

  String get _googleApiKey {
    final envKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;
    return _fallbackGoogleKey;
  }

  @override
  void initState() {
    super.initState();
    _visibility = widget.groupId != null ? 'group_only' : 'public';
    _loadUserProfile();
    _venueController.addListener(_onSearchChanged);

    // Round initial time
    final now = DateTime.now().add(const Duration(minutes: 60));
    _selectedDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute >= 30 ? 30 : 0,
    );
  }

  @override
  void dispose() {
    _inviteController.dispose();
    _inviteDebounce?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      final response = await SupabaseConfig.client
          .from('users')
          .select('display_name')
          .eq('id', user.id)
          .single();
      setState(() {
        _userName = response['display_name'];
      });
    }
  }

  Future<void> _pickMarkerImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) {
      setState(() {
        _markerImage = File(image.path);
      });
    }
  }

  // --- Date & Time Pickers (NEW) ---
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)), // 3 months out
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.indigo,
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            buttonTheme: const ButtonThemeData(
              textTheme: ButtonTextTheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.indigo,
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.indigo;
                }
                return Colors.black;
              }),
              hourMinuteColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.indigo.withOpacity(0.12);
                }
                return Colors.grey.shade200;
              }),
              dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.black; // Text color for unselected AM/PM
              }),
              dayPeriodColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.indigo;
                }
                return Colors.transparent; // Bg color for unselected AM/PM
              }),
              dialHandColor: Colors.indigo,
              dialBackgroundColor: Colors.grey[200],
              dialTextColor: Colors.black,
              entryModeIconColor: Colors.indigo,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  // --- Google Places Logic ---
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_venueController.text.isNotEmpty && _venueName == null) {
        // Only search if not already selected
        _getPlacePredictions(_venueController.text);
      } else {
        setState(() {
          _placePredictions = [];
          _showPredictions = false;
        });
      }
    });
  }

  Future<void> _getPlacePredictions(String input) async {
    try {
      var urlString =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$_googleApiKey';
      if (widget.currentLat != null && widget.currentLng != null) {
        urlString +=
            '&location=${widget.currentLat},${widget.currentLng}&radius=30000';
      }
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            _placePredictions = List<Map<String, dynamic>>.from(
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
            _showPredictions = true;
          });
        }
      }
    } catch (e) {
      print('❌ Places Error: $e');
    }
  }

  Future<void> _getPlaceDetails(String placeId, String description) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googleApiKey&fields=geometry,name,formatted_address',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];

          setState(() {
            _venueName = result['name'];
            _venueAddress = result['formatted_address'];
            _venueLat = location['lat'];
            _venueLng = location['lng'];
            _venueController.text = _venueName!; // Update text to venue name
            _showPredictions = false;
          });
        }
      }
    } catch (e) {
      print('❌ Place Details Error: $e');
    }
  }

  // --- Map Picker Logic (NEW) ---
  Future<void> _pickLocationOnMap() async {
    // Get current location for initial map position
    Position? currentPosition;
    try {
      // Check permissions logic if needed, or rely on LocationPickerModal to handle default
      // For now, let's pass null if we don't have it, or use widget.currentLat/Lng
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
    } catch (e) {
      // ignore
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LocationPickerModal(initialPosition: currentPosition),
      ),
    );

    if (result != null && result is Map) {
      final address = result['address'] as String?;
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;

      if (lat != null && lng != null) {
        setState(() {
          _venueAddress = address;
          _venueLat = lat;
          _venueLng = lng;
          // Use address as name if we picked from map
          _venueName = address;
          _venueController.text = address ?? '';
          _showPredictions = false;
        });
      }
    }
  }

  // --- Auto-GIF Keyword Map ---
  static const Map<String, String> _activityGifKeywords = {
    // Food & Drink
    'coffee': 'coffee cafe latte', 'cafe': 'coffee cafe',
    'tea': 'tea time drink', 'boba': 'boba milk tea',
    'milk tea': 'boba milk tea', 'eat': 'eating food delicious',
    'food': 'food eating yummy', 'lunch': 'lunch eating',
    'dinner': 'dinner date dining', 'breakfast': 'breakfast morning',
    'brunch': 'brunch food', 'snack': 'snacks food',
    'pizza': 'pizza eating', 'burger': 'burger eating',
    'sushi': 'sushi japanese food', 'ramen': 'ramen noodles',
    'bbq': 'bbq grill barbecue', 'grill': 'grill bbq cooking',
    'buffet': 'buffet all you can eat', 'dessert': 'dessert sweets',
    'ice cream': 'ice cream dessert', 'cake': 'cake dessert',
    'drink': 'drinks cheers', 'beer': 'beer cheers pub',
    'wine': 'wine cheers', 'cocktail': 'cocktail drinks bar',
    'bar': 'bar nightlife drinks', 'pub': 'pub drinks night',
    'samgyupsal': 'korean bbq samgyupsal', 'korean': 'korean food kbbq',
    'japanese': 'japanese food sushi', 'chinese': 'chinese food dim sum',
    'italian': 'italian food pasta', 'mexican': 'mexican food tacos',
    'thai': 'thai food spicy', 'seafood': 'seafood fresh',
    'steak': 'steak dinner', 'pasta': 'pasta italian',
    'chicken': 'fried chicken food', 'wings': 'chicken wings',
    
    // Sports & Fitness
    'run': 'running fitness jog', 'jog': 'jogging running',
    '5k': 'running marathon 5k', '10k': 'running marathon',
    'marathon': 'marathon running', 'gym': 'gym workout fitness',
    'workout': 'workout gym exercise', 'exercise': 'exercise fitness',
    'lift': 'weightlifting gym', 'crossfit': 'crossfit workout',
    'yoga': 'yoga meditation zen', 'pilates': 'pilates workout',
    'swim': 'swimming pool', 'surf': 'surfing waves beach',
    'basketball': 'basketball dunk nba', 'soccer': 'soccer football goal',
    'football': 'football soccer', 'volleyball': 'volleyball beach',
    'tennis': 'tennis match serve', 'badminton': 'badminton sport',
    'boxing': 'boxing punch workout', 'mma': 'mma fighting ufc',
    'muay thai': 'muay thai kickboxing', 'jiu jitsu': 'jiu jitsu bjj',
    'martial arts': 'martial arts karate', 'golf': 'golf swing hole',
    'bowling': 'bowling strike', 'bike': 'cycling bike ride',
    'cycle': 'cycling biking', 'hike': 'hiking mountain nature',
    'climb': 'rock climbing bouldering', 'skate': 'skateboarding tricks',
    'dance': 'dancing party moves', 'zumba': 'zumba dance fitness',
    
    // Entertainment & Social
    'movie': 'movie cinema popcorn', 'cinema': 'cinema movie theater',
    'netflix': 'netflix binge watching', 'watch': 'watching movie show',
    'party': 'party celebration fun', 'club': 'club nightlife party',
    'karaoke': 'karaoke singing mic', 'sing': 'singing karaoke music',
    'concert': 'concert live music', 'music': 'music vibes',
    'gig': 'concert live music gig', 'festival': 'music festival party',
    'game': 'gaming video games', 'gaming': 'gaming esports controller',
    'board game': 'board game fun', 'cards': 'card game poker',
    'poker': 'poker cards game', 'arcade': 'arcade games retro',
    'billiards': 'billiards pool table', 'pool': 'billiards pool game',
    'darts': 'darts pub game', 'trivia': 'trivia quiz night',
    
    // Outdoor & Travel
    'beach': 'beach summer vibes', 'camp': 'camping outdoor nature',
    'travel': 'travel adventure explore', 'road trip': 'road trip adventure',
    'explore': 'explore adventure travel', 'adventure': 'adventure explore',
    'dive': 'scuba diving ocean', 'snorkel': 'snorkeling ocean',
    'fish': 'fishing relaxing', 'park': 'park nature outdoor',
    'picnic': 'picnic outdoor food', 'sunset': 'sunset beautiful view',
    
    // Creative & Learning
    'study': 'studying books focus', 'read': 'reading books library',
    'book': 'books reading', 'paint': 'painting art creative',
    'draw': 'drawing art sketch', 'art': 'art creative painting',
    'photo': 'photography camera', 'cook': 'cooking chef kitchen',
    'bake': 'baking kitchen sweets', 'code': 'coding programming laptop',
    'hack': 'hackathon coding tech', 'work': 'coworking productive',
    'meeting': 'business meeting work', 'brainstorm': 'brainstorm ideas',
    
    // Relaxation & Wellness
    'spa': 'spa relaxation massage', 'massage': 'massage spa relax',
    'meditate': 'meditation zen calm', 'chill': 'chill relax vibes',
    'hang': 'hangout friends fun', 'hangout': 'hangout friends chill',
    'talk': 'talking conversation friends', 'catch up': 'catching up friends',
    'vibe': 'good vibes chill', 'shop': 'shopping mall retail',
    'mall': 'shopping mall fun', 'thrift': 'thrift shopping vintage',
  };

  /// Search Tenor for a GIF based on the activity text
  Future<String?> _getAutoGifUrl(String activityText) async {
    try {
      final lowerText = activityText.toLowerCase();
      String searchQuery = activityText; // Default: use the raw activity text

      // Try to match against keyword map for better results
      for (final entry in _activityGifKeywords.entries) {
        if (lowerText.contains(entry.key)) {
          searchQuery = entry.value;
          break;
        }
      }

      print('🎬 AUTO-GIF: Searching Tenor for "$searchQuery" (from: "$activityText")');

      final tenor = TenorService();
      final results = await tenor.searchGifs(searchQuery, limit: 5);

      if (results.isNotEmpty) {
        // Pick a random one from top 5 for variety
        final randomIndex = DateTime.now().millisecondsSinceEpoch % results.length;
        final gifUrl = tenor.getGifUrl(results[randomIndex]);
        if (gifUrl.isNotEmpty) {
          print('✅ AUTO-GIF: Found GIF: $gifUrl');
          return gifUrl;
        }
      }

      print('⚠️ AUTO-GIF: No results found');
      return null;
    } catch (e) {
      print('❌ AUTO-GIF: Error - $e');
      return null;
    }
  }

  // --- Invite User Search ---
  void _onInviteSearchChanged(String query) {
    print('🔍 Invite search onChanged: "$query"');
    if (_inviteDebounce?.isActive ?? false) _inviteDebounce!.cancel();
    _inviteDebounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _searchUsersForInvite(query.trim());
      } else {
        setState(() {
          _inviteSearchResults = [];
          _showInviteResults = false;
        });
      }
    });
  }

  Future<void> _searchUsersForInvite(String query) async {
    try {
      // Strip leading @ since usernames in DB don't have it
      final cleanQuery = query.startsWith('@') ? query.substring(1) : query;
      if (cleanQuery.isEmpty) return;
      print('🔍 Searching for invite: "$cleanQuery"');
      final results = await SocialService().searchUsers(cleanQuery, limit: 5);
      print('🔍 Search results: ${results.length} users found');
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      // Filter out already-invited users and self
      final filtered = results.where((u) {
        final uid = u['id'] as String;
        return uid != currentUserId &&
            !_invitedUsers.any((invited) => invited['id'] == uid);
      }).toList();
      print('🔍 Filtered results: ${filtered.length} users');
      if (mounted) {
        setState(() {
          _inviteSearchResults = filtered;
          _showInviteResults = filtered.isNotEmpty;
        });
      }
    } catch (e) {
      print('❌ Invite search error: $e');
    }
  }

  void _addInvitedUser(Map<String, dynamic> user) {
    setState(() {
      _invitedUsers.add(user);
      _inviteSearchResults = [];
      _showInviteResults = false;
      _inviteController.clear();
    });
  }

  void _removeInvitedUser(int index) {
    setState(() {
      _invitedUsers.removeAt(index);
    });
  }

  Map<String, dynamic>? _buildFiltersJson() {
    if (_genderFilter == 'everyone' && !_ageFilterEnabled) return null;
    final filters = <String, dynamic>{};
    if (_genderFilter != 'everyone') filters['gender'] = _genderFilter;
    if (_ageFilterEnabled) {
      filters['age_min'] = _ageRange.start.round();
      filters['age_max'] = _ageRange.end.round();
    }
    filters['enforcement'] = _enforcement;
    return filters;
  }

  // --- Creation Logic ---
  Future<void> _createTable() async {
    if (_activityController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('What do you want to do?')));
      return;
    }
    if (_venueLat == null || _venueLng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a venue')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final activity = _activityController.text.trim();
      // Use group name when creating for a group, else user name
      final hostLabel = widget.groupName ?? _userName ?? 'Someone';
      final title = '$hostLabel wants to $activity';
      final description = _descriptionController.text.trim(); // NEW

      // Only use GIF if user explicitly selected one (no auto-GIF fallback)
      String? finalImageUrl = _selectedGifUrl;

      await _tableService.createTable(
        latitude: _venueLat!,
        longitude: _venueLng!,
        scheduledTime: _selectedDateTime,
        activityType: 'other',
        venueName: _venueName!,
        venueAddress: _venueAddress!,
        title: title,
        description: description.isNotEmpty ? description : null,
        maxCapacity: _maxCapacity.round(),
        budgetMin: _budgetRange == 'low'
            ? 0
            : (_budgetRange == 'high' ? 50 : 20),
        budgetMax: _budgetRange == 'low'
            ? 20
            : (_budgetRange == 'high' ? 100 : 50),
        requiresApproval: _requiresApproval,
        goalType: _goalType,
        imageUrl: finalImageUrl,
        markerImage: _markerImage,
        markerEmoji: _markerImage == null
            ? (_selectedEmoji ?? '📍')
            : null,
        visibility: _visibility,
        filters: _buildFiltersJson(),
        invitedUserIds: _invitedUsers.isNotEmpty
            ? _invitedUsers.map((u) => u['id'] as String).toList()
            : null,
        groupId: widget.groupId,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onTableCreated();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Table created! 🎉')));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, error: e, fallbackMessage: 'Unable to create table. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height:
          MediaQuery.of(context).size.height * 0.95, // Taller for more content
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque, // Catch all taps
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  Expanded(
                    child: Text(
                      'Host an Activity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance close button
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior
                    .onDrag, // Dismiss on scroll
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group context banner
                    if (widget.groupId != null && widget.groupName != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.groups_outlined,
                                size: 20,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Creating for ${widget.groupName}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // I WANT TO... Input
                    Text(
                      'I want to...',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _activityController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        fontSize: 22,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'grab coffee, play tennis, etc.',
                        hintStyle: TextStyle(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // WHERE? Input (Venue)
                    Text(
                      'Where?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _venueController,
                      decoration: InputDecoration(
                        hintText: 'Search for a place',
                        prefixIcon: Icon(
                          Icons.search,
                          color: theme.iconTheme.color?.withOpacity(0.7),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.map_outlined),
                          color: theme.primaryColor,
                          tooltip: 'Pick on Map',
                          onPressed: _pickLocationOnMap,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (val) {
                        // Reset venue selection if user types
                        if (_venueName != null && val != _venueName) {
                          setState(() {
                            _venueName = null;
                            _venueLat = null;
                            _venueLng = null;
                          });
                        }
                      },
                    ),

                    // Predictions List
                    if (_showPredictions && _venueController.text.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: _placePredictions
                              .map(
                                (p) => ListTile(
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                    color: Colors.black54,
                                  ),
                                  title: Text(
                                    p['main_text'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    p['secondary_text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  onTap: () => _getPlaceDetails(
                                    p['place_id'],
                                    p['description'],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),

                    // DESCRIPTION / DETAILS (NEW)
                    const SizedBox(height: 24),
                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add description, menu links, etc...',
                        hintStyle: TextStyle(color: theme.hintColor),
                        filled: true,
                        fillColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[50], // Lighter background
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'When?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Date Chip
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                    color: theme.iconTheme.color?.withOpacity(
                                      0.7,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat(
                                      'EEE, MMM d',
                                    ).format(_selectedDateTime),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Time Chip
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickTime,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: theme.iconTheme.color?.withOpacity(
                                      0.7,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat(
                                      'h:mm a',
                                    ).format(_selectedDateTime),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ADD A VIBE (GIF)
                    GestureDetector(
                      onTap: () {
                        setState(() => _showGifPicker = !_showGifPicker);
                      },
                      child: Row(
                        children: [
                          Text(
                            'Add a Vibe (GIF)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedGifUrl != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Added ✅',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            Icon(
                              _showGifPicker
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Colors.grey,
                            ),
                        ],
                      ),
                    ),

                    if (_showGifPicker) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 450,
                        child: TenorGifPicker(
                          isEmbedded: true,
                          onGifSelected: (url) {
                            setState(() {
                              _selectedGifUrl = url;
                              _showGifPicker = false;
                            });
                          },
                        ),
                      ),
                    ],

                    // Show selected GIF preview
                    if (_selectedGifUrl != null) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          _selectedGifUrl!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: Center(
                                child: CircularProgressIndicator(
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // MARKER APPEARANCE (NEW GRID)
                    Text(
                      'Map Marker',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Image Upload Option (Large Card)
                    GestureDetector(
                      onTap: _pickMarkerImage,
                      child: Container(
                        height: 60,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _markerImage != null
                              ? Colors.green.withOpacity(0.1)
                              : (isDark ? Colors.grey[800] : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _markerImage != null
                                ? Colors.green
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _markerImage != null
                                  ? Icons.check_circle
                                  : Icons.camera_alt,
                              color: _markerImage != null
                                  ? Colors.green
                                  : theme.iconTheme.color?.withOpacity(0.7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _markerImage != null
                                  ? 'Custom Image Selected'
                                  : 'Upload Custom Image',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _markerImage != null
                                    ? (isDark
                                          ? Colors.green[300]
                                          : Colors.green[700])
                                    : theme.colorScheme.onSurface.withOpacity(
                                        0.8,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_markerImage == null) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: Text(
                          "OR CHOOSE AN EMOJI",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick Select + More Button
                      SizedBox(
                        height: 50,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // "More" Button
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) {
                                    return SizedBox(
                                      height: 400,
                                      child: EmojiPicker(
                                        onEmojiSelected: (category, emoji) {
                                          setState(() {
                                            _selectedEmoji = emoji.emoji;
                                          });
                                          Navigator.pop(context);
                                        },
                                        config: Config(
                                          height: 256,
                                          checkPlatformCompatibility: true,
                                          viewOrderConfig:
                                              const ViewOrderConfig(),
                                          emojiViewConfig: EmojiViewConfig(
                                            // Issue: https://github.com/flutter/flutter/issues/28894
                                            emojiSizeMax:
                                                28 *
                                                (foundation.defaultTargetPlatform ==
                                                        TargetPlatform.iOS
                                                    ? 1.20
                                                    : 1.0),
                                            backgroundColor: Colors.white,
                                            columns: 7,
                                          ),
                                          skinToneConfig:
                                              const SkinToneConfig(),
                                          categoryViewConfig:
                                              const CategoryViewConfig(
                                                indicatorColor: Colors.indigo,
                                                iconColorSelected:
                                                    Colors.indigo,
                                              ),
                                          bottomActionBarConfig:
                                              const BottomActionBarConfig(
                                                backgroundColor: Colors.white,
                                                buttonColor: Colors.white,
                                                buttonIconColor: Colors.grey,
                                              ),
                                          searchViewConfig:
                                              const SearchViewConfig(
                                                backgroundColor: Colors.white,
                                              ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: Colors.indigo.withOpacity(0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.add_reaction_outlined,
                                      color: Colors.indigo,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'More',
                                      style: TextStyle(
                                        color: Colors.indigo,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Common Emojis (subset)
                            ..._commonEmojis.take(10).map((emoji) {
                              final isSelected = _selectedEmoji == emoji;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedEmoji = emoji),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.only(right: 12),
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.indigo
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.indigo
                                          : Colors.grey[300]!,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.indigo.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      // Selected Preview (if picked from "More")
                      if (!_commonEmojis.take(10).contains(_selectedEmoji) &&
                          _selectedEmoji != '📍')
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Selected: ",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.indigo,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.indigo.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _selectedEmoji!,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 32),

                    // ATTENDEES (Capacity)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Max Guests',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        Text(
                          _maxCapacity.round().toString(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.black,
                        inactiveTrackColor: Colors.grey[200],
                        thumbColor: Colors.black,
                        overlayColor: Colors.black.withOpacity(0.1),
                        valueIndicatorColor: Colors.black,
                      ),
                      child: Slider(
                        value: _maxCapacity,
                        min: 2,
                        max: 30,
                        divisions: 28,
                        onChanged: (val) => setState(() => _maxCapacity = val),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // REQUIRE APPROVAL toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[200]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 20,
                            color: _requiresApproval
                                ? Colors.indigo
                                : Colors.grey[500],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Require Approval',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  'Review who joins before they enter',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _requiresApproval,
                            activeColor: Colors.indigo,
                            onChanged: (val) =>
                                setState(() => _requiresApproval = val),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ═══════════════════════════════════════
                    // VISIBILITY SELECTOR
                    // ═══════════════════════════════════════
                    Text(
                      'Who can see this?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _visibility = 'public'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _visibility == 'public'
                                    ? Colors.indigo
                                    : (isDark ? Colors.grey[800] : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _visibility == 'public'
                                      ? Colors.indigo
                                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.public,
                                    size: 18,
                                    color: _visibility == 'public'
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Public',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: _visibility == 'public'
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _visibility = 'followers_only'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _visibility == 'followers_only'
                                    ? Colors.indigo
                                    : (isDark ? Colors.grey[800] : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _visibility == 'followers_only'
                                      ? Colors.indigo
                                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 18,
                                    color: _visibility == 'followers_only'
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Followers',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: _visibility == 'followers_only'
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _visibility = 'mystery'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _visibility == 'mystery'
                                    ? const Color(0xFF7C3AED)
                                    : (isDark ? Colors.grey[800] : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _visibility == 'mystery'
                                      ? const Color(0xFF7C3AED)
                                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '🔮',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: _visibility == 'mystery'
                                          ? Colors.white
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Mystery',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: _visibility == 'mystery'
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Group-Only Option (only when creating for a group)
                        if (widget.groupId != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _visibility = 'group_only'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: _visibility == 'group_only'
                                      ? const Color(0xFF059669)
                                      : (isDark ? Colors.grey[800] : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _visibility == 'group_only'
                                        ? const Color(0xFF059669)
                                        : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 18,
                                      color: _visibility == 'group_only'
                                          ? Colors.white
                                          : Colors.grey[600],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Members',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: _visibility == 'group_only'
                                            ? Colors.white
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Mystery hint text
                    if (_visibility == 'mystery')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: const Color(0xFF7C3AED)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Only visible to people who scan this area with the walking pulse',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF7C3AED),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_visibility == 'group_only')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: const Color(0xFF059669)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Only group members can see this activity',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF059669),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ═══════════════════════════════════════
                    // INVITE PEOPLE BY HANDLE
                    // ═══════════════════════════════════════
                    Text(
                      'Invite People',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Search by @username to invite friends',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inviteController,
                      onChanged: _onInviteSearchChanged,
                      decoration: InputDecoration(
                        hintText: '@username',
                        prefixIcon: Icon(
                          Icons.alternate_email,
                          color: theme.iconTheme.color?.withOpacity(0.7),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),

                    // Invite Search Results
                    if (_showInviteResults && _inviteSearchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: _inviteSearchResults.map((user) {
                            final displayName = user['display_name'] ?? 'User';
                            final username = user['username'] ?? '';
                            final avatarUrl = user['avatar_url'];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundImage: avatarUrl != null
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: avatarUrl == null
                                    ? Text(
                                        displayName.isNotEmpty
                                            ? displayName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(fontSize: 14),
                                      )
                                    : null,
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: username.isNotEmpty
                                  ? Text(
                                      '@$username',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    )
                                  : null,
                              trailing: Icon(
                                Icons.add_circle_outline,
                                size: 20,
                                color: Colors.indigo,
                              ),
                              onTap: () => _addInvitedUser(user),
                            );
                          }).toList(),
                        ),
                      ),

                    // Invited Users Chips
                    if (_invitedUsers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_invitedUsers.length, (i) {
                          final user = _invitedUsers[i];
                          final name = user['display_name'] ?? 'User';
                          final username = user['username'] ?? '';
                          return Chip(
                            avatar: CircleAvatar(
                              radius: 12,
                              backgroundImage: user['avatar_url'] != null
                                  ? NetworkImage(user['avatar_url'])
                                  : null,
                              child: user['avatar_url'] == null
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 10),
                                    )
                                  : null,
                            ),
                            label: Text(
                              username.isNotEmpty ? '@$username' : name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeInvitedUser(i),
                            backgroundColor: isDark ? Colors.grey[800] : Colors.indigo.withOpacity(0.08),
                            side: BorderSide(
                              color: Colors.indigo.withOpacity(0.2),
                            ),
                          );
                        }),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ═══════════════════════════════════════
                    // ADVANCED FILTERS (Collapsible)
                    // ═══════════════════════════════════════
                    GestureDetector(
                      onTap: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune,
                            size: 20,
                            color: _showAdvancedFilters ? Colors.indigo : Colors.grey[500],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Advanced Filters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          // Show active indicator if any filter is set
                          if (_genderFilter != 'everyone' || _ageFilterEnabled)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  color: Colors.indigo,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Icon(
                            _showAdvancedFilters
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),

                    if (_showAdvancedFilters) ...[
                      const SizedBox(height: 16),

                      // Gender Preference
                      Text(
                        'Gender Preference',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _genderFilter,
                            isExpanded: true,
                            dropdownColor: isDark ? Colors.grey[800] : Colors.white,
                            items: const [
                              DropdownMenuItem(value: 'everyone', child: Text('Everyone Welcome 🌈')),
                              DropdownMenuItem(value: 'women_only', child: Text('Women Only 👩')),
                              DropdownMenuItem(value: 'men_only', child: Text('Men Only 👨')),
                              DropdownMenuItem(value: 'nonbinary_only', child: Text('Non-binary Only 🏳️‍🌈')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _genderFilter = val);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Age Range
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Age Range',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _ageFilterEnabled,
                            activeColor: Colors.indigo,
                            onChanged: (val) => setState(() => _ageFilterEnabled = val),
                          ),
                        ],
                      ),
                      if (_ageFilterEnabled) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_ageRange.start.round()} yrs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${_ageRange.end.round()} yrs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.indigo,
                            inactiveTrackColor: Colors.grey[200],
                            thumbColor: Colors.indigo,
                            overlayColor: Colors.indigo.withOpacity(0.1),
                            rangeThumbShape: const RoundRangeSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: RangeSlider(
                            values: _ageRange,
                            min: 18,
                            max: 65,
                            divisions: 47,
                            onChanged: (val) => setState(() => _ageRange = val),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Enforcement Mode
                      if (_genderFilter != 'everyone' || _ageFilterEnabled) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enforcement',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _enforcement = 'soft'),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _enforcement == 'soft'
                                              ? Colors.amber.withOpacity(0.15)
                                              : (isDark ? Colors.grey[700] : Colors.grey[100]),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _enforcement == 'soft'
                                                ? Colors.amber
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.label_outline,
                                              size: 20,
                                              color: _enforcement == 'soft'
                                                  ? Colors.amber[800]
                                                  : Colors.grey[500],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Soft Label',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _enforcement == 'soft'
                                                    ? Colors.amber[800]
                                                    : Colors.grey[500],
                                              ),
                                            ),
                                            Text(
                                              'Tag only',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _enforcement = 'hard'),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _enforcement == 'hard'
                                              ? Colors.red.withOpacity(0.1)
                                              : (isDark ? Colors.grey[700] : Colors.grey[100]),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _enforcement == 'hard'
                                                ? Colors.red
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.lock_outline,
                                              size: 20,
                                              color: _enforcement == 'hard'
                                                  ? Colors.red
                                                  : Colors.grey[500],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Enforced',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _enforcement == 'hard'
                                                    ? Colors.red
                                                    : Colors.grey[500],
                                              ),
                                            ),
                                            Text(
                                              'Blocks join',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 100), // Space for FAB
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createTable,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Create Activity',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
