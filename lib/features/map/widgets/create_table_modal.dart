import 'package:flutter/material.dart';

import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';

import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/shared/widgets/date_time_selector.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'dart:io';

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
  final _emojiController = TextEditingController(text: '📍'); // Default emoji
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
  double _maxCapacity = 4; // Changed to double for Slider
  String _budgetRange = 'medium';
  String _goalType = 'friends';
  bool _requiresApproval = false;
  bool _isLoading = false;

  // Visuals
  String? _selectedGifUrl;
  bool _showGifPicker = false;
  File? _markerImage;

  // Google Places
  List<Map<String, dynamic>> _placePredictions = [];
  Timer? _debounce;
  bool _showPredictions = false;
  String get _googleApiKey => dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';

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

  // ... (existing loadUserProfile, onSearchChanged, getPlacePredictions, getPlaceDetails methods)
  // I will preserve them by not overwriting them, but I need to be careful with range.
  // The user told me to keep existing code.
  // BUT I need to inject `_pickMarkerImage` and imports.
  // I'll assume the replacement covers the whole class content or I'll split it.

  // Actually, I can replace the whole file content efficiently since I have it all.
  // Wait, I should try to target specific blocks.

  // Block 1: Imports + Class Definition + State Variables
  // Block 2: _createTable method (updated arguments)
  // Block 3: build method (Group Size Slider + Marker Section)

  // Implementation below uses MultiReplace or just strategic single replace if allowed?
  // Tool `replace_file_content` says "use this tool ONLY when you are making a SINGLE CONTIGUOUS block of edits".
  // So I cannot do multiple blocks.
  // I will use `replace_file_content` on the `build` method primarily, and *another* call for imports/state?
  // No, sequential tool calls.

  // Let's replace the properties first.

  // Block 1: Properties & Imports.
  // I will add imports at the top.
  // Then I will add properties to `_CreateTableModalState`.

  // Block 2: `_createTable` and `build`.
  // These are contiguous if I include the helper methods in between or if they are close.
  // They are close. `_createTable` is at 156. `build` at 204.
  // So I can replace 156 to end of file to handle `_createTable` + `build`.

  // Let's do Imports first.
  // Lines 12-13.

  // Oops, I can only do ONE replace per turn? "Do NOT make multiple parallel calls to this tool".
  // I will start with Imports + State.
  // Wait, if I change state, the `build` method might error if I don't update it in the same turn?
  // No, Dart analysis happens after.

  // Actually, I'll rewrite the whole file in one go since I have the content and it's safer to ensure consistency.
  // 464 lines is manageable.
  // But strictly, "SINGULAR CONTIGUOUS BLOCK".
  // I will replace from line 1 (imports) to line 464?
  // That's fine.

  // Let's construct the full file.

  // WARNING: I need to keep `_loadUserProfile`, `_onSearchChanged`, `_getPlacePredictions`, `_getPlaceDetails` exactly as is.
  // Retyping them risks typos.

  // Better strategy:
  // 1. Add Imports.
  // 2. Add State fields.
  // 3. Update `_createTable` logic.
  // 4. Update `build` UI.

  // I'll do this in steps.
  // Step 1: Update Imports (lines 1-13).
  // Step 2: Update State (lines 31-59).
  // Step 3: Update `_createTable` (lines 156-201).
  // Step 4: Update `build` (lines 204-464).

  // Wait, I can do 1 and 2 in one go if I include the class decl.
  // No, imports are separated by class def.

  // I'll just use `multi_replace_file_content`!
  // It allows multiple chunks.

  // I will use `replace_file_content` for imports.
  // Then `replace_file_content` for State.
  // Wait, "Do NOT make multiple parallel calls".
  // I have to do 1 tool call.
  // `multi_replace_file_content` fits perfectly.

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

      await _tableService.createTable(
        latitude: _venueLat!,
        longitude: _venueLng!,
        scheduledTime: _selectedDateTime,
        activityType: 'other', // General type for custom activities
        venueName: _venueName!,
        venueAddress: _venueAddress!,
        title: title, // CUSTOM TITLE
        description: "", // Description is now implicit in the title
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
            ? (_emojiController.text.isEmpty ? '📍' : _emojiController.text)
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // I WANT TO... Input
                  const Text(
                    'I want to...',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _activityController,
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 22,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'grab coffee, play tennis, etc.',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // WHERE? Input (Venue)
                  Text(
                    'Where?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _venueController,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.black54,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
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

                  const SizedBox(height: 32),

                  // WHEN? (DateTime Selector)
                  Text(
                    'When?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DateTimeSelector(
                    initialDate: _selectedDateTime,
                    onDateTimeChanged: (dt) {
                      setState(() => _selectedDateTime = dt);
                    },
                  ),

                  const SizedBox(height: 32),

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
                            color: Colors.grey[800],
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

                  const SizedBox(height: 32),

                  // MARKER APPEARANCE (NEW)
                  Text(
                    'Map Marker',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Image Option
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickMarkerImage,
                          child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: _markerImage != null
                                  ? Border.all(color: Colors.black, width: 2)
                                  : null,
                              image: _markerImage != null
                                  ? DecorationImage(
                                      image: FileImage(_markerImage!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _markerImage == null
                                ? const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo,
                                        color: Colors.black54,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Add Image',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Emoji Option (Fallback)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _markerImage = null),
                          child: Container(
                            height: 80,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: _markerImage == null
                                  ? Border.all(color: Colors.black, width: 2)
                                  : null, // Highlight if no image
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Or use Emoji',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 30,
                                  child: TextField(
                                    controller: _emojiController,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 24),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    maxLength: 2, // 1 char + emoji sometimes 2?
                                    buildCounter:
                                        (
                                          _, {
                                          required currentLength,
                                          required isFocused,
                                          required maxLength,
                                        }) => null,
                                    onTap: () =>
                                        setState(() => _markerImage = null),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // DETAILS (Capacity, Budget, Approval)
                  // Use Slider for Capacity (2-30)
                  Text(
                    'Group Size: ${_maxCapacity.round()}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                      label: _maxCapacity.round().toString(),
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
                    backgroundColor: Colors.black,
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
    );
  }

  // Removed _buildCapacityButton helper as it's replaced by Slider
}
