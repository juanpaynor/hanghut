import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/theme/app_theme.dart';

import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/home/widgets/location_picker_modal.dart';

class CreateExperienceScreen extends StatefulWidget {
  final String partnerId;
  final Map<String, dynamic>? existingExperience;

  const CreateExperienceScreen({
    super.key,
    required this.partnerId,
    this.existingExperience,
  });

  @override
  State<CreateExperienceScreen> createState() => _CreateExperienceScreenState();
}

class _CreateExperienceScreenState extends State<CreateExperienceScreen> {
  final _hostService = HostService();
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingExperience != null;
  final int _totalSteps = 5;

  // Step 1 — Basics
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedType;

  // Step 2 — Media
  final List<String> _existingImageUrls = [];
  String? _existingVideoUrl;
  final List<File> _images = [];
  File? _videoFile;

  // Step 3 — Details
  final _requirementsController = TextEditingController();
  final _includedController = TextEditingController();
  final _maxGuestsController = TextEditingController(text: '6');

  // Step 4 — Pricing
  final _priceController = TextEditingController();
  String _currency = 'PHP';

  // Step 5 — Location
  final _locationNameController = TextEditingController();
  double _lat = 14.5995;
  double _lng = 120.9842;
  final List<Map<String, dynamic>> _itinerary = [];

  // Google Places & Map
  List<Map<String, dynamic>> _placePredictions = [];
  Timer? _debounce;
  bool _showPredictions = false;
  static const String _fallbackGoogleKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';

  String get _googleApiKey {
    final envKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;
    return _fallbackGoogleKey;
  }

  final _types = [
    ('workshop', '🎨', 'Workshop'),
    ('adventure', '🧗', 'Adventure'),
    ('food_tour', '🍜', 'Food Tour'),
    ('nightlife', '🎶', 'Nightlife'),
    ('culture', '🏛️', 'Culture'),
    ('other', '✨', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _locationNameController.addListener(_onSearchChanged);

    if (_isEditing) {
      final exp = widget.existingExperience!;
      _titleController.text = exp['title'] ?? '';
      _descController.text = exp['description'] ?? '';
      _selectedType = exp['experience_type'] ?? 'other';

      _existingImageUrls.addAll((exp['images'] as List?)?.cast<String>() ?? []);
      _existingVideoUrl = exp['video_url'];

      _requirementsController.text =
          ((exp['requirements'] as List?)?.cast<String>() ?? []).join('\n');
      _includedController.text =
          ((exp['included_items'] as List?)?.cast<String>() ?? []).join('\n');
      _maxGuestsController.text = exp['max_guests']?.toString() ?? '6';

      _priceController.text = exp['price_per_person']?.toString() ?? '';
      _currency = exp['currency'] ?? 'PHP';

      _locationNameController.text = exp['location_name'] ?? '';
      _lat = exp['latitude'] ?? 14.5995;
      _lng = exp['longitude'] ?? 120.9842;

      if (exp['itinerary'] != null) {
        final List<dynamic> rawItin = exp['itinerary'] is String
            ? jsonDecode(exp['itinerary'])
            : exp['itinerary'];
        _itinerary.addAll(rawItin.map((e) => Map<String, dynamic>.from(e)));
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _requirementsController.dispose();
    _includedController.dispose();
    _maxGuestsController.dispose();
    _priceController.dispose();
    _locationNameController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _pickImages() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maximum 5 images allowed')));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      setState(() {
        for (final img in picked) {
          if (_images.length < 5) {
            _images.add(File(img.path));
          }
        }
      });
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final sizeInMB = await file.length() / (1024 * 1024);
      if (sizeInMB > 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Video must be under 200MB. Please compress and try again.',
              ),
            ),
          );
        }
        return;
      }
      setState(() => _videoFile = file);
    }
  }

  Future<List<String>> _uploadImages() async {
    final supabase = SupabaseConfig.client;
    final urls = <String>[];
    for (final img in _images) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${urls.length}.jpg';
      await supabase.storage.from('experiences').upload(fileName, img);
      final url = supabase.storage.from('experiences').getPublicUrl(fileName);
      urls.add(url);
    }
    return urls;
  }

  Future<String?> _uploadVideo() async {
    if (_videoFile == null) return null;
    final supabase = SupabaseConfig.client;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_video.mp4';
    await supabase.storage
        .from('experience-videos')
        .upload(fileName, _videoFile!);
    return supabase.storage.from('experience-videos').getPublicUrl(fileName);
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      // Upload media
      final newImageUrls = await _uploadImages();
      final allImageUrls = [..._existingImageUrls, ...newImageUrls];
      final videoUrl = await _uploadVideo() ?? _existingVideoUrl;

      // Parse lists
      final requirements = _requirementsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final includedItems = _includedController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (_isEditing) {
        await _hostService.updateExperience(
          tableId: widget.existingExperience!['id'],
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          experienceType: _selectedType ?? 'other',
          images: allImageUrls,
          videoUrl: videoUrl,
          requirements: requirements,
          includedItems: includedItems,
          pricePerPerson: double.tryParse(_priceController.text) ?? 0,
          currency: _currency,
          maxGuests: int.tryParse(_maxGuestsController.text) ?? 6,
          locationName: _locationNameController.text.trim(),
          latitude: _lat,
          longitude: _lng,
          itinerary: _itinerary.isNotEmpty ? _itinerary : null,
        );
      } else {
        await _hostService.createExperience(
          partnerId: widget.partnerId,
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          experienceType: _selectedType ?? 'other',
          images: allImageUrls,
          videoUrl: videoUrl,
          requirements: requirements,
          includedItems: includedItems,
          pricePerPerson: double.tryParse(_priceController.text) ?? 0,
          currency: _currency,
          maxGuests: int.tryParse(_maxGuestsController.text) ?? 6,
          locationName: _locationNameController.text.trim(),
          latitude: _lat,
          longitude: _lng,
          itinerary: _itinerary.isNotEmpty ? _itinerary : null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Experience updated successfully!'
                  : '🎉 Experience submitted! Hanghut will review and verify it shortly.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Basics', 'Media', 'Details', 'Pricing', 'Location'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _currentStep > 0 ? Icons.arrow_back : Icons.close,
            color: Colors.black87,
          ),
          onPressed: _currentStep > 0
              ? _prevStep
              : () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit Experience' : 'Create Experience',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Text(
              'Step ${_currentStep + 1} of $_totalSteps — ${stepTitles[_currentStep]}',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: Colors.grey[200],
            color: AppTheme.primaryColor,
            minHeight: 3,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicsStep(),
                _buildMediaStep(),
                _buildDetailsStep(),
                _buildPricingStep(),
                _buildLocationStep(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _nextStep,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _currentStep < _totalSteps - 1
                            ? 'Continue'
                            : 'Submit for Review',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Basics ──────────────────────────────────────────────────────────
  Widget _buildBasicsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('What\'s your experience?'),
          const SizedBox(height: 24),
          _label('Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'e.g. Sunset Pottery Workshop',
            ),
          ),
          const SizedBox(height: 20),
          _label('Description'),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Describe what guests will do, see, and feel...',
            ),
          ),
          const SizedBox(height: 20),
          _label('Experience Type'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _types.map((type) {
              final isSelected = _selectedType == type.$1;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(type.$2, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        type.$3,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Media ───────────────────────────────────────────────────────────
  Widget _buildMediaStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Add photos & video'),
          const SizedBox(height: 8),
          Text(
            'Great photos dramatically increase bookings.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          _label('Photos (up to 5)'),
          const SizedBox(height: 12),
          // Image grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount:
                _existingImageUrls.length +
                _images.length +
                ((_existingImageUrls.length + _images.length) < 5 ? 1 : 0),
            itemBuilder: (context, i) {
              final totalImages = _existingImageUrls.length + _images.length;
              if (i == totalImages) {
                return GestureDetector(
                  onTap: _pickImages,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.grey[300]!,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Colors.grey[400],
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add',
                          style: GoogleFonts.inter(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final isExisting = i < _existingImageUrls.length;
              final imageProvider = isExisting
                  ? NetworkImage(_existingImageUrls[i])
                  : FileImage(_images[i - _existingImageUrls.length]);
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image(
                      image: imageProvider as ImageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        if (isExisting) {
                          _existingImageUrls.removeAt(i);
                        } else {
                          _images.removeAt(i - _existingImageUrls.length);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _label('Video (optional, max 200MB)'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickVideo,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: (_videoFile != null || _existingVideoUrl != null)
                  ? Row(
                      children: [
                        const Icon(
                          Icons.videocam,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _videoFile?.path.split('/').last ??
                                'Existing video attached',
                            style: GoogleFonts.inter(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _videoFile = null;
                            _existingVideoUrl = null;
                          }),
                          child: const Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 18,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Icon(
                          Icons.video_call_outlined,
                          size: 36,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to upload video',
                          style: GoogleFonts.inter(color: Colors.grey[500]),
                        ),
                        Text(
                          'MP4 or MOV • Max 200MB',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Details ─────────────────────────────────────────────────────────
  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Experience details'),
          const SizedBox(height: 24),
          _label('Requirements (one per line)'),
          const SizedBox(height: 8),
          TextField(
            controller: _requirementsController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g.\nComfortable shoes\nBring a water bottle',
            ),
          ),
          const SizedBox(height: 20),
          _label('What\'s included (one per line)'),
          const SizedBox(height: 8),
          TextField(
            controller: _includedController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g.\nAll materials\nLight snacks\nCertificate',
            ),
          ),
          const SizedBox(height: 20),
          _label('Max group size'),
          const SizedBox(height: 8),
          TextField(
            controller: _maxGuestsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 6'),
          ),
        ],
      ),
    );
  }

  // ── Step 4: Pricing ─────────────────────────────────────────────────────────
  Widget _buildPricingStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Set your price'),
          const SizedBox(height: 8),
          Text(
            'You\'ll receive your earnings after Hanghut\'s platform fee.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          _label('Price per person'),
          const SizedBox(height: 8),
          Row(
            children: [
              // Currency selector
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _currency,
                    items: ['PHP', 'USD', 'SGD']
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? 'PHP'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '0.00'),
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Fee breakdown preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _feeRow('Guest pays', _priceController.text, bold: true),
                const Divider(height: 20),
                _feeRow(
                  'Platform fee (15%)',
                  _calcFee(_priceController.text, 0.15),
                ),
                _feeRow(
                  'You receive',
                  _calcFee(_priceController.text, 0.85),
                  bold: true,
                  color: Colors.green[700],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _calcFee(String priceStr, double multiplier) {
    final price = double.tryParse(priceStr) ?? 0;
    return '$_currency ${(price * multiplier).toStringAsFixed(2)}';
  }

  Widget _feeRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.grey[700], fontSize: 14),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.black87,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ── Google Places & Map Logic ────────────────────────────────────────────────

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_locationNameController.text.isNotEmpty &&
          _locationNameController.text !=
              _placePredictions.firstOrNull?['main_text']) {
        // Only search if it looks like a new query (simple check)
        // Better check: if we just selected a place, we might want to avoid re-searching immediately if the text matches.
        // For now, let's just search.
        _getPlacePredictions(_locationNameController.text);
      } else {
        setState(() {
          _placePredictions = [];
          _showPredictions = false;
        });
      }
    });
  }

  Future<void> _getPlacePredictions(String input) async {
    debugPrint(
      '🔍 Searching Places for: "$input" using key: ${_googleApiKey.substring(0, 5)}...',
    );
    try {
      var urlString =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$_googleApiKey';
      // Bias towards current location if available
      urlString += '&location=$_lat,$_lng&radius=30000';

      final response = await http.get(Uri.parse(urlString));
      debugPrint('📥 Places Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📦 Places Data Status: ${data['status']}');

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
          debugPrint('✅ Found ${_placePredictions.length} predictions');
        } else {
          debugPrint(
            '⚠️ Places Error: ${data['status']} - ${data['error_message']}',
          );
          setState(() {
            _placePredictions = [];
            _showPredictions = false;
          });
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Places Exception: $e');
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
            _locationNameController.text =
                result['name']; // Use name as location name
            // Optionally store address separately if needed, but for experiences "Location Name" is usually what we want displayed
            // We could append address if we want.
            _lat = location['lat'];
            _lng = location['lng'];
            _showPredictions = false;
            _placePredictions = [];
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Place Details Error: $e');
    }
  }

  Future<void> _pickLocationOnMap() async {
    // Get current location for initial map position
    Position? currentPosition;
    try {
      currentPosition = Position(
        longitude: _lng,
        latitude: _lat,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
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
          _lat = lat;
          _lng = lng;
          // Use address as name if we picked from map
          if (address != null && address.isNotEmpty) {
            _locationNameController.text = address;
          }
          _showPredictions = false;
        });
      }
    }
  }

  // ── Step 5: Location ────────────────────────────────────────────────────────
  Widget _buildLocationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Where will it happen?'),
          const SizedBox(height: 24),
          _label('Meeting point'),
          const SizedBox(height: 8),

          // Search Input with Map Button
          TextField(
            controller: _locationNameController,
            decoration: InputDecoration(
              hintText: 'Search for a place',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: IconButton(
                icon: const Icon(Icons.map_outlined),
                color: AppTheme.primaryColor,
                tooltip: 'Pick on Map',
                onPressed: _pickLocationOnMap,
              ),
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            onChanged: (val) {
              // Logic is handled by listener, but we might want to clear lat/lng if user clears text
              if (val.isEmpty) {
                // optionally reset lat/lng or keep last known
              }
            },
          ),

          // Predictions List
          if (_showPredictions)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          p['secondary_text'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        onTap: () =>
                            _getPlaceDetails(p['place_id'], p['description']),
                      ),
                    )
                    .toList(),
              ),
            ),

          const SizedBox(height: 20),

          const SizedBox(height: 32),
          _sectionTitle('Itinerary (Optional)'),
          const SizedBox(height: 8),
          Text(
            'Add stops to create a full routed experience. If you only meet at one location, skip this.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          _buildItineraryList(),
          const SizedBox(height: 32),

          // Value Preview (Optional, to show lat/lng confirmation)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.my_location, size: 20, color: Colors.grey[400]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coordinates',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      Text(
                        '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItineraryList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_itinerary.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _itinerary.length,
            separatorBuilder: (context, i) => const Divider(height: 24),
            itemBuilder: (context, i) {
              final stop = _itinerary[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.inter(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop['title'] ?? '',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stop['description'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _itinerary.removeAt(i)),
                  ),
                ],
              );
            },
          ),
        if (_itinerary.isNotEmpty) const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    _AddItineraryStopScreen(initialLat: _lat, initialLng: _lng),
              ),
            );
            if (result != null && result is Map<String, dynamic>) {
              setState(() => _itinerary.add(result));
            }
          },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add Stop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: BorderSide(color: AppTheme.primaryColor),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}

class _AddItineraryStopScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const _AddItineraryStopScreen({
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<_AddItineraryStopScreen> createState() =>
      _AddItineraryStopScreenState();
}

class _AddItineraryStopScreenState extends State<_AddItineraryStopScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  late double _lat;
  late double _lng;
  String _locationName = 'Select Location';

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  Future<void> _pickLocation() async {
    final currentPosition = Position(
      longitude: _lng,
      latitude: _lat,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

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
          _lat = lat;
          _lng = lng;
          if (address != null && address.isNotEmpty) {
            _locationName = address;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Add Itinerary Stop',
          style: GoogleFonts.inter(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              if (_titleController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a title')),
                );
                return;
              }
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'description': _descController.text.trim(),
                'location_name': _locationName,
                'lat': _lat,
                'lng': _lng,
              });
            },
            child: Text(
              'Save',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop Title',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'e.g. Stop 1: Intramuros',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Description',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What will guests do here?',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Location',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickLocation,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _locationName,
                        style: GoogleFonts.inter(color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
}
