import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/profile_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:confetti/confetti.dart';
import 'package:country_picker/country_picker.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final PageController _pageController = PageController();
  final ProfileService _profileService = ProfileService();
  late ConfettiController _confettiController;

  // Fixed Theme Colors (User Requirement: Indigo + Light Theme)
  static const Color _primaryColor = Color(0xFF6B7FFF); // Indigo
  static const Color _backgroundColor = Colors.white;
  static const Color _textColor = Colors.black;
  static const Color _secondaryTextColor = Color(0xFF757575);

  int _currentStep = 0;
  final int _totalSteps = 5; // Added photo step
  bool _isLoading = false;

  // Step 1: Photos
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedPhoto;
  String? _uploadedPhotoUrl;

  // Step 2: Basics Controllers
  final _bioController = TextEditingController();
  Country? _selectedCountry;
  DateTime? _dateOfBirth;
  String? _genderIdentity;
  final List<String> _genderOptions = [
    'Male',
    'Female',
    'Non-binary',
    'Prefer not to say',
    'Other',
  ];

  // Step 3: Personality Questions
  final Map<int, int?> _personalityAnswers = {}; // questionIndex -> score (1-5)

  // Personality questions with answer options
  final List<Map<String, dynamic>> _personalityQuestions = [
    {
      'question': 'Friday Night Plans?',
      'trait': 'extraversion',
      'options': [
        {'text': '🎉 Hit the town, meet new people', 'score': 5},
        {'text': '🍷 Small gathering with close friends', 'score': 3},
        {'text': '📚 Cozy night in, just me', 'score': 1},
      ],
    },
    {
      'question': 'Your Ideal Dinner Spot?',
      'trait': 'openness',
      'options': [
        {'text': '🌮 Hole-in-the-wall place I\'ve never tried', 'score': 5},
        {'text': '🍝 Trendy spot my friend recommended', 'score': 3},
        {'text': '🍔 My favorite restaurant, every time', 'score': 1},
      ],
    },
    {
      'question': 'Planning a Trip?',
      'trait': 'conscientiousness',
      'options': [
        {'text': '📋 Itinerary planned weeks ahead', 'score': 5},
        {'text': '🗺️ Rough plan, room for spontaneity', 'score': 3},
        {'text': '✈️ Book the flight, figure it out later', 'score': 1},
      ],
    },
    {
      'question': 'Someone disagrees with you at dinner?',
      'trait': 'agreeableness',
      'options': [
        {'text': '🤝 Listen, find common ground', 'score': 5},
        {'text': '💬 Healthy debate, no hard feelings', 'score': 3},
        {'text': '🔥 Stand my ground, I\'m right', 'score': 1},
      ],
    },
    {
      'question': 'When things go wrong?',
      'trait': 'neuroticism',
      'options': [
        {'text': '😰 I stress until it\'s fixed', 'score': 5},
        {'text': '😅 Frustrated but move on quickly', 'score': 3},
        {'text': '😎 Roll with it, no big deal', 'score': 1},
      ],
    },
    {
      'question': 'Group chat vibe?',
      'trait': 'extraversion',
      'options': [
        {'text': '💬 Always replying, starting convos', 'score': 5},
        {'text': '👀 I read everything, chime in sometimes', 'score': 3},
        {'text': '🔕 Notifications off, check weekly', 'score': 1},
      ],
    },
    {
      'question': 'Trying new food?',
      'trait': 'openness',
      'options': [
        {'text': '🦗 Bring on the weird stuff', 'score': 5},
        {'text': '🍜 Adventurous within reason', 'score': 3},
        {'text': '🍕 Stick to what I know', 'score': 1},
      ],
    },
    {
      'question': 'Your workspace?',
      'trait': 'conscientiousness',
      'options': [
        {'text': '🧹 Spotless, color-coded', 'score': 5},
        {'text': '📂 Organized chaos', 'score': 3},
        {'text': '🌪️ Creative mess', 'score': 1},
      ],
    },
    {
      'question': 'Meeting new people?',
      'trait': 'extraversion',
      'options': [
        {'text': '😊 Energizing, love it!', 'score': 5},
        {'text': '🙂 Fine, but draining', 'score': 3},
        {'text': '😬 Prefer to avoid', 'score': 1},
      ],
    },
    {
      'question': 'After a bad day?',
      'trait': 'neuroticism',
      'options': [
        {'text': '😢 I need to vent/cry', 'score': 5},
        {'text': '😕 Process it, then I\'m good', 'score': 3},
        {'text': '🤷 Bad days don\'t phase me', 'score': 1},
      ],
    },
  ];

  Map<String, int> _calculatePersonalityScores() {
    final traitScores = <String, List<int>>{
      'openness': [],
      'conscientiousness': [],
      'extraversion': [],
      'agreeableness': [],
      'neuroticism': [],
    };

    _personalityAnswers.forEach((questionIndex, score) {
      if (score != null) {
        final trait = _personalityQuestions[questionIndex]['trait'] as String;
        traitScores[trait]!.add(score);
      }
    });

    return traitScores.map((trait, scores) {
      final avg = scores.isEmpty
          ? 3
          : (scores.reduce((a, b) => a + b) / scores.length).round();
      return MapEntry(trait, avg);
    });
  }

  // Step 4: Interests
  final Set<String> _selectedInterestIds = {};
  List<Map<String, dynamic>> _availableInterests = [];

  // Step 5: Preferences
  RangeValues _budgetRange = const RangeValues(20, 100);
  String _primaryGoal = 'friends'; // friends, romance, casual

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _fetchInterests();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bioController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _fetchInterests() async {
    try {
      final tags = await _profileService.getInterestTags();
      if (mounted) {
        setState(() {
          _availableInterests = tags;
        });
      }
    } catch (e) {
      debugPrint('Error fetching interests: $e');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (photo != null) {
        setState(() {
          _selectedPhoto = photo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking photo: $e')));
      }
    }
  }

  Future<String?> _uploadPhoto() async {
    if (_selectedPhoto == null) return null;

    try {
      // Get current session and user
      final session = SupabaseConfig.client.auth.currentSession;
      final currentUser = SupabaseConfig.client.auth.currentUser;

      print('📸 UPLOAD: Session exists: ${session != null}');
      print(
        '📸 UPLOAD: Access token: ${session?.accessToken?.substring(0, 20) ?? "null"}...',
      );
      print('📸 UPLOAD: Current user: ${currentUser?.id}');
      print('📧 UPLOAD: Email: ${currentUser?.email}');

      final userId = currentUser?.id;
      if (userId == null) {
        print('❌ UPLOAD: No user ID found!');
        print('❌ UPLOAD: Session is null: ${session == null}');
        throw Exception('User not logged in - no session');
      }

      print('✅ UPLOAD: User authenticated, proceeding with upload...');

      final bytes = await _selectedPhoto!.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$userId/$timestamp.jpg';

      // Upload to Supabase storage with user ID folder
      await SupabaseConfig.client.storage
          .from('profile-photos')
          .uploadBinary(filePath, bytes);

      // Get public URL
      final publicUrl = SupabaseConfig.client.storage
          .from('profile-photos')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
      }
      return null;
    }
  }

  void _nextPage() async {
    // If on photo step and photo is selected, upload it first
    if (_currentStep == 0 &&
        _selectedPhoto != null &&
        _uploadedPhotoUrl == null) {
      setState(() => _isLoading = true);
      _uploadedPhotoUrl = await _uploadPhoto();
      setState(() => _isLoading = false);

      if (_uploadedPhotoUrl == null) {
        // Upload failed, don't proceed
        return;
      }
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    } else {
      _completeSetup();
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      final personalityScores = _calculatePersonalityScores();

      await _profileService.createProfile(
        userId: userId,
        bio: _bioController.text,
        dob: _dateOfBirth ?? DateTime(2000),
        gender: _genderIdentity ?? 'Prefer not to say',
        personality: personalityScores,
        interestTagIds: _selectedInterestIds.toList(),
        preferences: {
          'budget_min': _budgetRange.start.round(),
          'budget_max': _budgetRange.end.round(),
          'primary_goal': _primaryGoal,
        },
        photoUrl: _uploadedPhotoUrl,
      );

      // Play Confetti! 🎉
      _confettiController.play();

      // Wait for confetti to play a bit before navigating
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Force Light Theme
    return Theme(
      data: AppTheme.lightTheme.copyWith(
        scaffoldBackgroundColor: _backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryColor,
          primary: _primaryColor,
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        backgroundColor: _backgroundColor,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Header with Progress
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        if (_currentStep > 0)
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: _textColor,
                            ),
                            onPressed: _previousPage,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        else
                          IconButton(
                            icon: const Icon(
                              Icons.logout,
                              color: AppTheme.errorColor,
                            ),
                            onPressed: () async {
                              await SupabaseConfig.client.auth.signOut();
                              if (mounted) {
                                Navigator.of(context).pushReplacementNamed('/');
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),

                        const SizedBox(width: 16),

                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (_currentStep + 1) / _totalSteps,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                _primaryColor,
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        Text(
                          '${_currentStep + 1}/$_totalSteps',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _textColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildPhotoStep(),
                        _buildBasicsStep(),
                        _buildPersonalityStep(),
                        _buildInterestsStep(),
                        _buildPreferencesStep(),
                      ],
                    ),
                  ),

                  // Bottom Action Button
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: _primaryColor.withValues(alpha: 0.4),
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
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _currentStep == _totalSteps - 1
                                    ? 'Complete Setup'
                                    : 'Continue',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Confetti Overlay
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  _primaryColor,
                  Colors.pink,
                  Colors.orange,
                  Colors.blue,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Text(
            'Add your photo',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _textColor,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn().moveY(begin: 20, end: 0),

          const SizedBox(height: 8),

          Text(
            'Show your smile! This helps others recognize you.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: _secondaryTextColor,
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 100.ms).moveY(begin: 20, end: 0),

          const SizedBox(height: 48),

          // Photo Preview/Picker
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _selectedPhoto != null
                  ? ClipOval(
                      child: Image.file(
                        File(_selectedPhoto!.path),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to add photo',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ).animate().scale(delay: 300.ms),

          if (_selectedPhoto != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.refresh),
              label: const Text('Change photo'),
              style: TextButton.styleFrom(foregroundColor: Colors.black),
            ),
          ],

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can skip this and add a photo later from your profile',
                    style: TextStyle(color: Colors.blue[900], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ).animate().fadeIn().moveY(begin: 20, end: 0),

          const SizedBox(height: 8),

          Text(
            'This helps others get to know you better.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).moveY(begin: 20, end: 0),

          const SizedBox(height: 32),

          // Bio
          const Text(
            'Bio',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Write a short bio...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Country
          const Text(
            'Country',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              showCountryPicker(
                context: context,
                showPhoneCode: false,
                countryListTheme: CountryListThemeData(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  inputDecoration: InputDecoration(
                    labelText: 'Search',
                    hintText: 'Start typing to search',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
                onSelect: (Country country) {
                  setState(() => _selectedCountry = country);
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.public, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _selectedCountry == null
                        ? 'Select Country'
                        : '${_selectedCountry!.flagEmoji} ${_selectedCountry!.name}',
                    style: TextStyle(
                      color: _selectedCountry == null
                          ? Colors.grey[600]
                          : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Date of Birth
          const Text(
            'Date of Birth',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now().subtract(
                  const Duration(days: 365 * 18),
                ),
                firstDate: DateTime(1900),
                lastDate: DateTime.now().subtract(
                  const Duration(days: 365 * 18),
                ),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Colors.black,
                        onPrimary: Colors.white,
                        onSurface: Colors.black,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (date != null) {
                setState(() => _dateOfBirth = date);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _dateOfBirth == null
                        ? 'Select Date'
                        : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                    style: TextStyle(
                      color: _dateOfBirth == null
                          ? Colors.grey[600]
                          : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Gender Identity
          const Text(
            'Gender Identity',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _genderIdentity,
                hint: Text(
                  'Select Gender',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: _genderOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _genderIdentity = newValue;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Vibe Check',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ).animate().fadeIn().moveY(begin: 20, end: 0),

          const SizedBox(height: 8),

          Text(
            'Answer these quick questions so we can find your crowd.',
            style: const TextStyle(
              fontSize: 16,
              color: _secondaryTextColor,
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 100.ms).moveY(begin: 20, end: 0),

          const SizedBox(height: 32),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _personalityQuestions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 32),
            itemBuilder: (context, index) {
              return _buildQuestionCard(index, _personalityQuestions[index])
                  .animate()
                  .fadeIn(delay: (200 + (index * 50)).ms)
                  .moveY(begin: 20, end: 0);
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index, Map<String, dynamic> question) {
    final selectedAnswer = _personalityAnswers[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question['question'] as String,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: _textColor,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate((question['options'] as List).length, (optionIndex) {
          final option = question['options'][optionIndex];
          final hasSelection = selectedAnswer != null;
          final isSelected = selectedAnswer == option['score'];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _personalityAnswers[index] = option['score'] as int;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : Colors.white,
                  border: Border.all(
                    color: isSelected
                        ? _primaryColor
                        : (hasSelection
                              ? Colors.grey[200]!
                              : Colors.grey[300]!),
                    width: isSelected ? 2 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option['text'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : _textColor,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      )
                    else
                      Icon(
                        Icons.circle_outlined,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInterestsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Interests',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ).animate().fadeIn().moveY(begin: 20, end: 0),

          const SizedBox(height: 8),

          Text(
            'Select at least 3 things you love.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).moveY(begin: 20, end: 0),

          const SizedBox(height: 32),

          Wrap(
            spacing: 8,
            runSpacing: 12,
            children: _availableInterests.map((interest) {
              final id = interest['id'] as String;
              final name = interest['name'] as String;
              final isSelected = _selectedInterestIds.contains(id);
              return FilterChip(
                label: Text(name),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedInterestIds.add(id);
                    } else {
                      _selectedInterestIds.remove(id);
                    }
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: Colors.black,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? Colors.black : Colors.grey[300]!,
                  ),
                ),
                showCheckmark: false,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preferences',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ).animate().fadeIn().moveY(begin: 20, end: 0),

          const SizedBox(height: 8),

          Text(
            'Set your boundaries and goals.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).moveY(begin: 20, end: 0),

          const SizedBox(height: 32),

          // Budget
          const Text(
            'Budget per person (\$)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          RangeSlider(
            values: _budgetRange,
            min: 0,
            max: 200,
            divisions: 20,
            activeColor: Colors.black,
            inactiveColor: Colors.grey[200],
            labels: RangeLabels(
              '\$${_budgetRange.start.round()}',
              '\$${_budgetRange.end.round()}',
            ),
            onChanged: (values) {
              setState(() {
                _budgetRange = values;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${_budgetRange.start.round()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${_budgetRange.end.round()}+',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Primary Goal
          const Text(
            'What are you looking for?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 16),
          _buildGoalOption('friends', 'Friends', Icons.people_outline),
          const SizedBox(height: 12),
          _buildGoalOption('romance', 'Romance', Icons.favorite_border),
          const SizedBox(height: 12),
          _buildGoalOption('casual', 'Casual Hangout', Icons.coffee_outlined),
        ],
      ),
    );
  }

  Widget _buildGoalOption(String value, String label, IconData icon) {
    final isSelected = _primaryGoal == value;
    return InkWell(
      onTap: () => setState(() => _primaryGoal = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey[300]!,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white)
            else
              Icon(Icons.circle_outlined, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
