
import 'package:flutter/material.dart';

import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';

import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/shared/widgets/date_time_selector.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


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
  final _tableService = TableService();

  // User Profile
  String? _userName;
  
  // Form State
  String? _venueName;
  String? _venueAddress;
  double? _venueLat;
  double? _venueLng;
  DateTime _selectedDateTime = DateTime.now().add(const Duration(minutes: 60)); // Default 1 hour from now
  int _maxCapacity = 4;
  String _budgetRange = 'medium';
  String _goalType = 'friends';
  bool _requiresApproval = false;
  bool _isLoading = false;
  
  // Visuals
  String? _selectedGifUrl;
  bool _showGifPicker = false;

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
      now.year, now.month, now.day, now.hour, now.minute >= 30 ? 30 : 0
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

  // --- Google Places Logic ---
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_venueController.text.isNotEmpty && _venueName == null) { // Only search if not already selected
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
      var urlString = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$_googleApiKey';
      if (widget.currentLat != null && widget.currentLng != null) {
        urlString += '&location=${widget.currentLat},${widget.currentLng}&radius=30000';
      }
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            _placePredictions = List<Map<String, dynamic>>.from(data['predictions'].map((p) => {
              'place_id': p['place_id'],
              'description': p['description'],
              'main_text': p['structured_formatting']['main_text'],
              'secondary_text': p['structured_formatting']['secondary_text'],
            }));
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
      final url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googleApiKey&fields=geometry,name,formatted_address');
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('What do you want to do?')));
      return;
    }
    if (_venueLat == null || _venueLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a venue')));
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
        maxCapacity: _maxCapacity,
        budgetMin: _budgetRange == 'low' ? 0 : (_budgetRange == 'high' ? 50 : 20),
        budgetMax: _budgetRange == 'low' ? 20 : (_budgetRange == 'high' ? 100 : 50),
        requiresApproval: _requiresApproval,
        goalType: _goalType,
        imageUrl: _selectedGifUrl,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onTableCreated();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Table created! 🎉')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  const Text('I want to...', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _activityController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 22, color: Colors.black, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'grab coffee, play tennis, etc.',
                      hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w400),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  
                  const SizedBox(height: 32),

                  // WHERE? Input (Venue)
                  Text('Where?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _venueController,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      prefixIcon: const Icon(Icons.search, color: Colors.black54),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        children: _placePredictions.map((p) => ListTile(
                          leading: const Icon(Icons.location_on_outlined, color: Colors.black54),
                          title: Text(p['main_text'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p['secondary_text'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          onTap: () => _getPlaceDetails(p['place_id'], p['description']),
                        )).toList(),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // WHEN? (DateTime Selector)
                  Text('When?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
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
                        Text('Add a Vibe (GIF)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                        const Spacer(),
                        if (_selectedGifUrl != null) 
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                            child: const Text('Added ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          )
                        else
                          Icon(_showGifPicker ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
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

                  // DETAILS (Capacity, Budget, Approval) - Collapsed for simplicity in this flow?
                  // Keeping them simple horizontal options
                  Text('Group Size', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildCapacityButton(2),
                      const SizedBox(width: 8),
                      _buildCapacityButton(4),
                      const SizedBox(width: 8),
                      _buildCapacityButton(6),
                      const SizedBox(width: 8),
                      _buildCapacityButton(8),
                    ],
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
  
  // -- Helper Widgets --
  
  Widget _buildCapacityButton(int size) {
    final isSelected = _maxCapacity == size;
    return GestureDetector(
      onTap: () => setState(() => _maxCapacity = size),
      child: Container(
        width: 48, 
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$size',
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

