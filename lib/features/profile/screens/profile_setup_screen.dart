import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/profile_service.dart';
import 'package:bitemates/core/services/image_crop_service.dart';
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
  final int _totalSteps = 3;
  bool _isLoading = false;

  // Step 1: Photos
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedPhoto;
  String? _uploadedPhotoUrl;

  // Step 2: Basics Controllers
  final _nameController = TextEditingController(); // Added Name Controller
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _usernameError;
  Country? _selectedCountry;
  DateTime? _dateOfBirth;
  String? _genderIdentity;
  final List<String> _genderOptions = [
    'Male',
    'Female',
    'Transgender Man',
    'Transgender Woman',
    'Non-binary',
    'Genderqueer',
    'Genderfluid',
    'Agender',
    'Two-Spirit',
    'Intersex',
    'Prefer not to say',
    'Other',
  ];

  // Step 3: Interests
  final Set<String> _selectedInterestIds = {};
  List<Map<String, dynamic>> _availableInterests = [];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _fetchInterests();

    // Pre-fill name if available
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.userMetadata?['full_name'] != null) {
      _nameController.text = user!.userMetadata!['full_name'];
    } else if (user?.userMetadata?['name'] != null) {
      _nameController.text = user!.userMetadata!['name'];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _validateUsername(String value) async {
    final username = value.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() => _usernameError = null);
      return;
    }
    if (username.length < 3) {
      setState(() => _usernameError = 'At least 3 characters');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() => _usernameError = 'Only letters, numbers, and underscores');
      return;
    }
    try {
      final available = await SupabaseConfig.client.rpc(
        'check_username_available',
        params: {'p_username': username},
      );
      if (mounted) {
        setState(() {
          _usernameError = available == true ? null : 'Username already taken';
        });
      }
    } catch (e) {
      debugPrint('Error checking username: $e');
    }
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
        // Cut the flow to crop the image
        if (mounted) {
          final croppedFile = await ImageCropService.cropImage(
            sourcePath: photo.path,
            context: context,
          );

          if (croppedFile != null) {
            setState(() {
              _selectedPhoto = XFile(croppedFile.path);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Could not select photo',
        );
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
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Could not upload photo',
        );
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

      await _profileService.createProfile(
        userId: userId,
        displayName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : 'User',
        username: _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim().toLowerCase()
            : null,
        bio: _bioController.text.trim(),
        dob: _dateOfBirth ?? DateTime(2000),
        gender: _genderIdentity ?? 'Prefer not to say',
        personality: const {},
        interestTagIds: _selectedInterestIds.toList(),
        preferences: const {},
        photoUrl: _uploadedPhotoUrl,
        nationality: _selectedCountry != null
            ? '${_selectedCountry!.flagEmoji} ${_selectedCountry!.name}'
            : null,
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
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Could not save your profile',
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
                        _buildInterestsStep(),
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
            'Add your profile photo. Pick a shot that represents you best — people are more likely to say "hi" to a friendly face.',
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
                    'No rush — you can always add one later from your profile.',
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

          // Name
          const Text(
            'Name',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Your name',
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

          // Username
          const Text(
            'Choose a username',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'This is your unique handle. Others can find you with it.',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            onChanged: _validateUsername,
            decoration: InputDecoration(
              hintText: 'e.g. richsantos',
              prefixIcon: Container(
                width: 40,
                alignment: Alignment.center,
                child: const Text(
                  '@',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              errorText: _usernameError,
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
            'Select up to 8 things you love.',
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
}
