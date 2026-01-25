import 'package:flutter/material.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
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

  const CreateTableModal({
    super.key,
    this.currentLat,
    this.currentLng,
    required this.onTableCreated,
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
      final title = '${_userName ?? "Someone"} wants to $activity';
      final description = _descriptionController.text.trim(); // NEW

      await _tableService.createTable(
        latitude: _venueLat!,
        longitude: _venueLng!,
        scheduledTime: _selectedDateTime,
        activityType: 'other', // General type for custom activities
        venueName: _venueName!,
        venueAddress: _venueAddress!,
        title: title, // CUSTOM TITLE
        description: description.isNotEmpty
            ? description
            : null, // Pass description
        maxCapacity: _maxCapacity.round(), // Convert double to int
        budgetMin: _budgetRange == 'low'
            ? 0
            : (_budgetRange == 'high' ? 50 : 20),
        budgetMax: _budgetRange == 'low'
            ? 20
            : (_budgetRange == 'high' ? 100 : 50),
        requiresApproval: _requiresApproval,
        goalType: _goalType,
        imageUrl: _selectedGifUrl,
        markerImage: _markerImage, // PASS MARKER IMAGE
        markerEmoji: _markerImage == null
            ? (_selectedEmoji ?? '📍')
            : null, // Default to emoji if no image
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                      'Host a Table',
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
                            'Create Table',
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
