import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/trip_service.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AddTripModal extends StatefulWidget {
  final VoidCallback onTripCreated;

  const AddTripModal({super.key, required this.onTripCreated});

  @override
  State<AddTripModal> createState() => _AddTripModalState();
}

class _AddTripModalState extends State<AddTripModal> {
  final _formKey = GlobalKey<FormState>();
  final _cityController =
      TextEditingController(); // Used as Main Destination Input
  final _countryController =
      TextEditingController(); // Hidden, populated via parse
  final _descriptionController = TextEditingController();

  // IMPORTANT: Replace with your actual Google Places API key!
  static const String _fallbackGoogleKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';

  String get _googleApiKey {
    final envKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;
    return _fallbackGoogleKey;
  }

  DateTime? _startDate;
  DateTime? _endDate;
  String _travelStyle = 'moderate';
  List<String> _selectedInterests = [];
  List<String> _selectedGoals = [];
  bool _isLoading = false;

  final List<Map<String, dynamic>> _travelStyles = [
    {
      'value': 'budget',
      'label': '💰 Budget',
      'description': 'Hostels, street food',
    },
    {
      'value': 'moderate',
      'label': '🎯 Moderate',
      'description': 'Mix of comfort & value',
    },
    {
      'value': 'luxury',
      'label': '✨ Luxury',
      'description': 'Premium experiences',
    },
  ];

  final List<Map<String, String>> _interests = [
    {'value': 'food', 'label': '🍜 Food & Dining'},
    {'value': 'nightlife', 'label': '🌃 Nightlife'},
    {'value': 'culture', 'label': '🏛️ Culture & History'},
    {'value': 'adventure', 'label': '🏔️ Adventure'},
    {'value': 'relaxation', 'label': '🧘 Relaxation'},
    {'value': 'shopping', 'label': '🛍️ Shopping'},
    {'value': 'photography', 'label': '📸 Photography'},
    {'value': 'nature', 'label': '🌿 Nature'},
  ];

  final List<Map<String, String>> _goals = [
    {'value': 'make_friends', 'label': 'Make new friends'},
    {'value': 'find_companion', 'label': 'Find travel companion'},
    {'value': 'local_tips', 'label': 'Get local tips'},
    {'value': 'group_activities', 'label': 'Join group activities'},
  ];

  @override
  void dispose() {
    _cityController.dispose();
    _countryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black, // Primary for selection circle
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              secondary: Color(0xFFFFC107), // Yellow accent
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _createTrip() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select travel dates')),
      );
      return;
    }
    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one interest')),
      );
      return;
    }
    if (_selectedGoals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one goal')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final tripService = TripService();
      await tripService.createTrip({
        'user_id': user.id,
        'destination_city': _cityController.text.trim().split(',').first,
        'destination_country': _countryController.text.isNotEmpty
            ? _countryController.text.trim()
            : _cityController.text.trim().split(',').last,
        'start_date': _startDate!.toIso8601String().split('T')[0],
        'end_date': _endDate!.toIso8601String().split('T')[0],
        'travel_style': _travelStyle,
        'interests': _selectedInterests,
        'goals': _selectedGoals,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'status': 'upcoming',
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip added successfully! 🎉')),
        );
        widget.onTripCreated();
      }
    } catch (e) {
      print('❌ Error creating trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating trip: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // AppTheme Colors
    final primaryColor = Theme.of(context).primaryColor;
    final accentColor = Theme.of(
      context,
    ).colorScheme.primary; // Use primary as accent for now
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Plan a Trip',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.black54),
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Destination (Google Places)
                      const Text(
                        'Where are you going?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: GooglePlaceAutoCompleteTextField(
                          textEditingController: _cityController,
                          googleAPIKey: _googleApiKey,
                          inputDecoration: InputDecoration(
                            hintText: 'Search for a city...',
                            hintStyle: const TextStyle(color: Colors.black38),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(
                              Icons.location_on,
                              color: Colors.black54,
                            ),
                            filled: true,
                            fillColor:
                                Colors.transparent, // Handled by Container
                          ),
                          debounceTime: 800, // Debounce 800ms
                          isLatLngRequired: false,
                          getPlaceDetailWithLatLng: (Prediction prediction) {
                            // Not needed for simple city/country
                          },
                          itemClick: (Prediction prediction) {
                            _cityController.text = prediction.description ?? '';
                            _cityController
                                .selection = TextSelection.fromPosition(
                              TextPosition(offset: _cityController.text.length),
                            );

                            // Simple Parsing: "City, Country"
                            final parts = (prediction.description ?? '').split(
                              ',',
                            );
                            if (parts.length > 1) {
                              _countryController.text = parts.last.trim();
                            } else {
                              _countryController.text = parts.first.trim();
                            }

                            // Dismiss keyboard after selection
                            FocusScope.of(context).unfocus();

                            setState(() {}); // Refresh UI if needed
                          },
                          // Customizing the list item
                          itemBuilder: (context, index, Prediction prediction) {
                            return Container(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_city,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(prediction.description ?? ''),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Dates
                      const Text(
                        'When?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _startDate == null || _endDate == null
                                      ? 'Select dates'
                                      : '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}',
                                  style: TextStyle(
                                    color: _startDate == null
                                        ? Colors.black38
                                        : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (_startDate != null && _endDate != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_endDate!.difference(_startDate!).inDays + 1} days',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Travel Style
                      const Text(
                        'Travel style',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._travelStyles.map((style) {
                        final isSelected = _travelStyle == style['value'];
                        return GestureDetector(
                          onTap: () => setState(
                            () => _travelStyle = style['value'] as String,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor.withOpacity(0.2)
                                  : surfaceColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? accentColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  style['label'] as String,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  style['description'] as String,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 24),

                      // Interests
                      const Text(
                        'What are you interested in?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _interests.map((interest) {
                          final isSelected = _selectedInterests.contains(
                            interest['value'],
                          );
                          return ChoiceChip(
                            label: Text(interest['label']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedInterests.add(interest['value']!);
                                } else {
                                  _selectedInterests.remove(interest['value']);
                                }
                              });
                            },
                            backgroundColor: surfaceColor,
                            selectedColor: accentColor,
                            labelStyle: TextStyle(
                              color: Colors.black,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide.none,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Goals
                      const Text(
                        'What are you looking for?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _goals.map((goal) {
                          final isSelected = _selectedGoals.contains(
                            goal['value'],
                          );
                          return ChoiceChip(
                            label: Text(goal['label']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedGoals.add(goal['value']!);
                                } else {
                                  _selectedGoals.remove(goal['value']);
                                }
                              });
                            },
                            backgroundColor: surfaceColor,
                            selectedColor: accentColor,
                            labelStyle: TextStyle(
                              color: Colors.black,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide.none,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Description
                      const Text(
                        'Tell us about your trip (optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          hintText:
                              'What are you planning to do? Any specific goals?',
                          hintStyle: const TextStyle(color: Colors.black38),
                          filled: true,
                          fillColor: surfaceColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Create button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createTrip,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
                                  'Add Trip',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
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
