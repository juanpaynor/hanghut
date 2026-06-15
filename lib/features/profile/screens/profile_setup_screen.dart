import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:country_picker/country_picker.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/core/services/profile_service.dart';
import 'package:bitemates/core/services/image_crop_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';

/// Per-step accent palette. Background stays a soft gradient white with a faint
/// glow in these tones so the frosted-glass cards have something to refract.
class _StepTheme {
  final Color accent;
  final Color accentLight;
  const _StepTheme({required this.accent, required this.accentLight});
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // Single Hanghut brand theme — consistent across every step.
  static const _theme = _StepTheme(accent: Color(0xFF6B7FFF), accentLight: Color(0xFFA5B0FF));

  final _pageController = PageController();
  final _profileService = ProfileService();
  int _currentStep = 0;
  static const _totalSteps = 4;
  bool _isLoading = false;
  bool _showCompletion = false;

  // Step 1 — Photo
  final _imagePicker = ImagePicker();
  XFile? _selectedPhoto;
  String? _uploadedPhotoUrl;

  // Step 2 — Identity
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  String? _usernameError;
  bool _usernameAvailable = false;
  bool _checkingUsername = false;
  Timer? _usernameTimer;

  // Step 3 — About
  final _bioController = TextEditingController();
  Country? _selectedCountry;
  int _selectedDay = 1;
  int _selectedMonth = 1;
  int _selectedYear = 2000;
  late FixedExtentScrollController _dayController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _yearController;
  String? _genderIdentity;

  static const _genderOptions = ['Male', 'Female', 'Non-binary', 'Other', 'Prefer not to say'];

  // Step 4 — Interests
  final _selectedInterestIds = <String>{};
  List<Map<String, dynamic>> _availableInterests = [];
  static const _maxInterests = 8;

  static final _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static final _days = List.generate(31, (i) => '${i + 1}');
  static final _years = List.generate(81, (i) => '${DateTime.now().year - 18 - i}');

  @override
  void initState() {
    super.initState();
    final defaultYearIndex = (DateTime.now().year - 18) - 2000;
    _dayController = FixedExtentScrollController(initialItem: 0);
    _monthController = FixedExtentScrollController(initialItem: 0);
    _yearController = FixedExtentScrollController(initialItem: defaultYearIndex.clamp(0, 80));

    _nameController.addListener(() => setState(() {}));
    _fetchInterests();

    final meta = SupabaseConfig.client.auth.currentUser?.userMetadata;
    if (meta?['full_name'] != null) {
      _nameController.text = meta!['full_name'];
    } else if (meta?['name'] != null) {
      _nameController.text = meta!['name'];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    _usernameTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInterests() async {
    try {
      final tags = await _profileService.getInterestTags();
      if (mounted) setState(() => _availableInterests = tags);
    } catch (_) {}
  }

  Future<void> _validateUsername(String value) async {
    _usernameTimer?.cancel();
    final username = value.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() { _usernameError = null; _usernameAvailable = false; });
      return;
    }
    if (username.length < 3) {
      setState(() { _usernameError = 'At least 3 characters'; _usernameAvailable = false; });
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() { _usernameError = 'Letters, numbers, underscores only'; _usernameAvailable = false; });
      return;
    }
    setState(() { _checkingUsername = true; _usernameError = null; _usernameAvailable = false; });
    _usernameTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final available = await SupabaseConfig.client.rpc('check_username_available', params: {'p_username': username});
        if (mounted) {
          setState(() {
            _checkingUsername = false;
            _usernameAvailable = available == true;
            _usernameError = available == true ? null : 'Username already taken';
          });
        }
      } catch (_) {
        if (mounted) setState(() => _checkingUsername = false);
      }
    });
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    try {
      final photo = await _imagePicker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (photo != null && mounted) {
        final cropped = await ImageCropService.cropImage(sourcePath: photo.path, context: context);
        if (cropped != null && mounted) {
          setState(() { _selectedPhoto = XFile(cropped.path); _uploadedPhotoUrl = null; });
        }
      }
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, error: e, fallbackMessage: 'Could not select photo');
    }
  }

  Future<String?> _uploadPhoto() async {
    if (_selectedPhoto == null) return null;
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      final bytes = await _selectedPhoto!.readAsBytes();
      final filePath = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await SupabaseConfig.client.storage.from('profile-photos').uploadBinary(filePath, bytes);
      return SupabaseConfig.client.storage.from('profile-photos').getPublicUrl(filePath);
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, error: e, fallbackMessage: 'Could not upload photo');
      return null;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1A1A2E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  void _nextPage() async {
    if (_currentStep == 0 && _selectedPhoto != null && _uploadedPhotoUrl == null) {
      setState(() => _isLoading = true);
      _uploadedPhotoUrl = await _uploadPhoto();
      setState(() => _isLoading = false);
      if (_uploadedPhotoUrl == null) return;
    }
    if (_currentStep == 1) {
      if (_nameController.text.trim().isEmpty) {
        _showSnack('Please enter your name');
        return;
      }
      final username = _usernameController.text.trim();
      if (username.isNotEmpty) {
        if (_checkingUsername) {
          _showSnack('Still checking username, please wait...');
          return;
        }
        if (!_usernameAvailable) {
          _showSnack('Fix your username before continuing');
          return;
        }
      }
    }
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
      setState(() => _currentStep++);
    } else {
      _completeSetup();
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
      setState(() => _currentStep--);
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      await _profileService.createProfile(
        userId: userId,
        displayName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Explorer',
        username: _usernameController.text.trim().isNotEmpty ? _usernameController.text.trim().toLowerCase() : null,
        bio: _bioController.text.trim(),
        dob: DateTime(_selectedYear, _selectedMonth, _selectedDay),
        gender: _genderIdentity ?? 'Prefer not to say',
        personality: const {},
        interestTagIds: _selectedInterestIds.toList(),
        preferences: const {},
        photoUrl: _uploadedPhotoUrl,
        nationality: _selectedCountry != null ? '${_selectedCountry!.flagEmoji} ${_selectedCountry!.name}' : null,
      );
      if (mounted) setState(() { _isLoading = false; _showCompletion = true; });
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, error: e, fallbackMessage: 'Could not save your profile');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: theme.accent, primary: theme.accent, brightness: Brightness.light),
      ),
      child: Scaffold(
        body: Stack(
          children: [
            _buildBackground(theme),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildPhotoStep(theme),
                        _buildIdentityStep(theme),
                        _buildAboutStep(theme),
                        _buildInterestsStep(theme),
                      ],
                    ),
                  ),
                  _buildBottomBar(theme),
                ],
              ),
            ),
            if (_showCompletion)
              _CompletionOverlay(
                name: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Explorer',
                photoPath: _selectedPhoto?.path,
                accent: theme.accent,
                interests: _availableInterests.where((i) => _selectedInterestIds.contains(i['id'])).toList(),
                onDone: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Gradient-white background with soft accent glows (for glass to refract) ────

  Widget _buildBackground(_StepTheme theme) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Base gradient white
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFF4F5FA)],
              ),
            ),
          ),
          // Soft accent glow — top
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            top: -120,
            right: -80,
            child: _glow(theme.accent, 360),
          ),
          // Soft accent glow — bottom
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            bottom: -140,
            left: -90,
            child: _glow(theme.accentLight, 380),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────────

  Widget _buildHeader(_StepTheme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          _glassIconButton(
            icon: _currentStep > 0 ? Icons.arrow_back_ios_new_rounded : Icons.logout_rounded,
            color: _currentStep > 0 ? Colors.black87 : Colors.red[400]!,
            onTap: _currentStep > 0
                ? _previousPage
                : () async {
                    await SupabaseConfig.client.auth.signOut();
                    if (mounted) Navigator.of(context).pushReplacementNamed('/');
                  },
          ),
          const Spacer(),
          Row(
            children: List.generate(_totalSteps, (i) {
              final isActive = i == _currentStep;
              final isDone = i < _currentStep;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 26 : 9,
                height: 9,
                decoration: BoxDecoration(
                  color: isActive ? theme.accent : isDone ? theme.accent.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
          const Spacer(),
          Text('${_currentStep + 1}/$_totalSteps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.3))),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _glassIconButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(_StepTheme theme) {
    final canSkip = _currentStep == 0 || _currentStep == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _isLoading ? null : _nextPage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [theme.accentLight, theme.accent]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: theme.accent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              alignment: Alignment.center,
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_currentStep == _totalSteps - 1 ? 'Finish' : 'Continue', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                      ],
                    ),
            ),
          ),
          if (canSkip) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _nextPage,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text('Skip for now', style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.3), fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 1 — Photo ────────────────────────────────────────────────────────────

  Widget _buildPhotoStep(_StepTheme theme) {
    final hasPhoto = _selectedPhoto != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _showPhotoSheet,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: theme.accent.withValues(alpha: 0.35), width: 4),
                    boxShadow: [BoxShadow(color: theme.accent.withValues(alpha: 0.25), blurRadius: 34, offset: const Offset(0, 14))],
                  ),
                  child: hasPhoto
                      ? Padding(padding: const EdgeInsets.all(5), child: ClipOval(child: Image.file(File(_selectedPhoto!.path), fit: BoxFit.cover, width: 158, height: 158)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded, size: 40, color: theme.accent),
                            const SizedBox(height: 8),
                            Text('Tap to add', style: TextStyle(color: theme.accent, fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
                if (hasPhoto)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.accent, border: Border.all(color: Colors.white, width: 3)),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
                  ),
              ],
            ),
          ).animate().scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 700.ms, curve: Curves.elasticOut).fadeIn(),
          const SizedBox(height: 30),
          Text(
            hasPhoto ? 'Looking sharp' : 'Add your photo',
            key: ValueKey(hasPhoto),
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: Color(0xFF1A1A2E)),
          ).animate(key: ValueKey('t$hasPhoto')).fadeIn().moveY(begin: 12, end: 0, curve: Curves.easeOutBack),
          const SizedBox(height: 8),
          Text(
            hasPhoto ? 'Tap the photo to change it anytime.' : 'A friendly face helps people connect.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.black.withValues(alpha: 0.45), height: 1.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: _photoOption(theme, Icons.camera_alt_rounded, 'Camera', () => _pickPhoto(source: ImageSource.camera))),
              const SizedBox(width: 12),
              Expanded(child: _photoOption(theme, Icons.photo_library_rounded, 'Gallery', () => _pickPhoto(source: ImageSource.gallery))),
            ],
          ).animate().fadeIn(delay: 300.ms).moveY(begin: 20, end: 0, curve: Curves.easeOutBack),
        ],
      ),
    );
  }

  Widget _photoOption(_StepTheme theme, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: _glassWrap(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Column(
            children: [
              Icon(icon, size: 24, color: theme.accent),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: Icon(Icons.camera_alt_rounded, color: _theme.accent), title: const Text('Take a photo'), onTap: () { Navigator.pop(context); _pickPhoto(source: ImageSource.camera); }),
              ListTile(leading: Icon(Icons.photo_library_rounded, color: _theme.accent), title: const Text('Choose from gallery'), onTap: () { Navigator.pop(context); _pickPhoto(source: ImageSource.gallery); }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 2 — Identity ────────────────────────────────────────────────────────

  Widget _buildIdentityStep(_StepTheme theme) {
    final name = _nameController.text;
    final showName = name.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          _glassIconBadge(Icons.person_rounded, theme),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: Center(
              child: Text(
                showName ? name : 'Who are you?',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: showName ? 34 : 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: showName ? theme.accent : Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Your name'),
                const SizedBox(height: 8),
                _textField(theme, controller: _nameController, hint: 'e.g. Alex Santos', textCapitalization: TextCapitalization.words),
                const SizedBox(height: 20),
                _label('Username'),
                const SizedBox(height: 4),
                Text('Your unique handle — others find you with this.', style: TextStyle(fontSize: 12.5, color: Colors.black.withValues(alpha: 0.4))),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameController,
                  onChanged: _validateUsername,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: _inputDecoration(theme, hint: 'e.g. alexsantos').copyWith(
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 2),
                      child: Text('@', style: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _checkingUsername
                        ? Padding(padding: const EdgeInsets.all(15), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400])))
                        : _usernameAvailable
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1FC8A4), size: 22).animate().scale(duration: 350.ms, curve: Curves.elasticOut)
                            : _usernameError != null
                                ? const Icon(Icons.cancel_rounded, color: Color(0xFFFF6F91), size: 22).animate().shakeX(amount: 3, duration: 350.ms)
                                : null,
                    errorText: _usernameError,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3 — About ────────────────────────────────────────────────────────────

  Widget _buildAboutStep(_StepTheme theme) {
    final age = DateTime.now().year - _selectedYear;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          _glassIconBadge(Icons.cake_rounded, theme),
          const SizedBox(height: 14),
          Text(
            '${_months[_selectedMonth - 1]} $_selectedDay, $_selectedYear',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.accent, letterSpacing: -0.5),
          ),
          Text('$age years old', style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _glassCard(child: _buildDrumPicker(theme)),
          const SizedBox(height: 14),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Where are you from?'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => showCountryPicker(
                    context: context,
                    showPhoneCode: false,
                    countryListTheme: CountryListThemeData(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      inputDecoration: InputDecoration(labelText: 'Search', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!))),
                    ),
                    onSelect: (c) => setState(() => _selectedCountry = c),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: _selectedCountry != null ? theme.accent.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _selectedCountry != null ? theme.accent.withValues(alpha: 0.45) : Colors.grey[200]!, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.public_rounded, size: 20, color: _selectedCountry != null ? theme.accent : Colors.black.withValues(alpha: 0.3)),
                        const SizedBox(width: 12),
                        Text(
                          _selectedCountry?.name ?? 'Select your country',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _selectedCountry == null ? Colors.black.withValues(alpha: 0.35) : const Color(0xFF1A1A2E)),
                        ),
                        const Spacer(),
                        Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black.withValues(alpha: 0.3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _label('Gender'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _genderOptions.map((label) {
                    final isSelected = _genderIdentity == label;
                    return GestureDetector(
                      onTap: () => setState(() => _genderIdentity = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? theme.accent : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: isSelected ? theme.accent : Colors.grey[200]!, width: 1.5),
                        ),
                        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : Colors.black.withValues(alpha: 0.6))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                _label('Bio'),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    _textField(theme, controller: _bioController, hint: 'What makes you, you...', maxLines: 3, maxLength: 160),
                    Positioned(
                      bottom: 10,
                      right: 14,
                      child: ValueListenableBuilder(
                        valueListenable: _bioController,
                        builder: (_, val, __) {
                          final count = val.text.length;
                          return Text('$count/160', style: TextStyle(fontSize: 11, color: count > 140 ? Colors.orange : Colors.black.withValues(alpha: 0.3), fontWeight: FontWeight.w600));
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrumPicker(_StepTheme theme) {
    return Column(
      children: [
        // Column labels
        Row(
          children: ['Day', 'Month', 'Year'].map((label) => Expanded(
            child: Center(
              child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.35), letterSpacing: 0.8)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 172,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 44,
                decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              ),
              Row(
                children: [
                  Expanded(child: _wheel(items: _days, controller: _dayController, selectedIndex: _selectedDay - 1, theme: theme, onChanged: (i) => setState(() => _selectedDay = i + 1))),
                  Expanded(child: _wheel(items: _months, controller: _monthController, selectedIndex: _selectedMonth - 1, theme: theme, onChanged: (i) => setState(() => _selectedMonth = i + 1))),
                  Expanded(child: _wheel(items: _years, controller: _yearController, selectedIndex: (DateTime.now().year - 18) - _selectedYear, theme: theme, onChanged: (i) => setState(() => _selectedYear = int.parse(_years[i])))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Scroll each column', style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.28), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _wheel({required List<String> items, required FixedExtentScrollController controller, required int selectedIndex, required _StepTheme theme, required ValueChanged<int> onChanged}) {
    return Column(
      children: [
        Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: theme.accent.withValues(alpha: 0.4)),
        Expanded(
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 44,
            perspective: 0.004,
            diameterRatio: 1.6,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: items.length,
              builder: (context, index) {
                final isSelected = index == selectedIndex;
                return Center(
                  child: Text(items[index], style: TextStyle(fontSize: isSelected ? 19 : 14, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500, color: isSelected ? theme.accent : Colors.black.withValues(alpha: 0.3))),
                );
              },
            ),
          ),
        ),
        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: theme.accent.withValues(alpha: 0.4)),
      ],
    );
  }

  // ── Step 4 — Interests ──────────────────────────────────────────────────────────

  Widget _buildInterestsStep(_StepTheme theme) {
    final selected = _selectedInterestIds.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: selected / _maxInterests),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => CircularProgressIndicator(value: value, strokeWidth: 7, backgroundColor: theme.accent.withValues(alpha: 0.15), valueColor: AlwaysStoppedAnimation(theme.accent), strokeCap: StrokeCap.round),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$selected', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: theme.accent, height: 1)),
                  Text('of $_maxInterests', style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ).animate().scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 18),
          const Text('What do you love?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          Text('Pick up to $_maxInterests things.', style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.45), fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: _availableInterests.asMap().entries.map((entry) {
              final id = entry.value['id'] as String;
              final name = entry.value['name'] as String;
              final isSelected = _selectedInterestIds.contains(id);
              final atMax = _selectedInterestIds.length >= _maxInterests;
              return GestureDetector(
                onTap: () {
                  if (!isSelected && atMax) return;
                  setState(() {
                    if (isSelected) { _selectedInterestIds.remove(id); }
                    else { _selectedInterestIds.add(id); }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: isSelected ? theme.accent : Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isSelected ? theme.accent : Colors.white.withValues(alpha: 0.8), width: 1.5),
                    boxShadow: isSelected
                        ? [BoxShadow(color: theme.accent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
                        : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Text(
                    name,
                    style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : (atMax ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.6))),
                  ),
                ),
              ).animate(delay: (entry.key * 30).ms).fadeIn(duration: 280.ms).moveY(begin: 18, end: 0, duration: 320.ms, curve: Curves.easeOutBack);
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────────────────

  /// Frosted-glass wrapper with a soft outer shadow.
  Widget _glassWrap({required Widget child, double radius = 24}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return _glassWrap(
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ).animate().fadeIn(duration: 400.ms, delay: 150.ms).moveY(begin: 26, end: 0, duration: 450.ms, curve: Curves.easeOutBack);
  }

  Widget _glassIconBadge(IconData icon, _StepTheme theme) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: theme.accent.withValues(alpha: 0.22), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.55),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
            ),
            child: Icon(icon, size: 38, color: theme.accent),
          ),
        ),
      ),
    ).animate().scale(begin: const Offset(0.4, 0.4), end: const Offset(1, 1), duration: 700.ms, curve: Curves.elasticOut).fadeIn();
  }

  Widget _label(String text) => Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)));

  InputDecoration _inputDecoration(_StepTheme theme, {required String hint}) {
    return InputDecoration(
      hintText: hint,
      counter: const SizedBox.shrink(),
      hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontWeight: FontWeight.w400),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[200]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[200]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: theme.accent, width: 1.8)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF6F91))),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF6F91), width: 1.8)),
    );
  }

  Widget _textField(_StepTheme theme, {required TextEditingController controller, required String hint, int maxLines = 1, int? maxLength, TextCapitalization textCapitalization = TextCapitalization.none}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: _inputDecoration(theme, hint: hint),
    );
  }
}

// ── Completion Overlay — premium morphing reveal ──────────────────────────────────

class _CompletionOverlay extends StatelessWidget {
  final String name;
  final String? photoPath;
  final Color accent;
  final List<Map<String, dynamic>> interests;
  final VoidCallback onDone;

  const _CompletionOverlay({required this.name, required this.photoPath, required this.accent, required this.interests, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final chips = interests.take(6).toList();
    final hasPhoto = photoPath != null;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F1024), Color(0xFF26224F), Color(0xFF1A1B3A)]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Avatar morph with glowing halo
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 4),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 48, spreadRadius: 8)],
                ),
                child: ClipOval(
                  child: hasPhoto
                      ? Image.file(File(photoPath!), fit: BoxFit.cover)
                      : Container(color: Colors.white.withValues(alpha: 0.18), child: const Icon(Icons.person_rounded, size: 62, color: Colors.white)),
                ),
              ).animate().scale(begin: const Offset(0.3, 0.3), end: const Offset(1, 1), duration: 800.ms, delay: 200.ms, curve: Curves.elasticOut).fadeIn(delay: 200.ms),
              const SizedBox(height: 34),
              Text('Welcome,', style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600, letterSpacing: 2))
                  .animate().fadeIn(duration: 400.ms, delay: 900.ms).moveY(begin: 14, end: 0),
              const SizedBox(height: 8),
              _NameSlam(name: name),
              const SizedBox(height: 48),
              if (chips.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: chips.asMap().entries.map((entry) {
                    final cName = entry.value['name'] as String? ?? '';
                    final delay = 1600 + (entry.key * 90);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                      child: Text(cName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ).animate().fadeIn(duration: 400.ms, delay: delay.ms).moveY(begin: 24, end: 0, duration: 450.ms, delay: delay.ms, curve: Curves.easeOutBack);
                  }).toList(),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: GestureDetector(
                  onTap: onDone,
                  child: Container(
                    width: double.infinity,
                    height: 58,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 6))]),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Start exploring', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20, color: accent),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 2200.ms).moveY(begin: 30, end: 0, curve: Curves.easeOutBack),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }
}

class _NameSlam extends StatelessWidget {
  final String name;
  const _NameSlam({required this.name});

  @override
  Widget build(BuildContext context) {
    final chars = name.split('');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: chars.asMap().entries.map((entry) {
        final delay = 1000 + (entry.key * 65);
        return Text(
          entry.value,
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5, height: 1),
        ).animate().fadeIn(duration: 300.ms, delay: delay.ms).moveY(begin: 38, end: 0, duration: 450.ms, delay: delay.ms, curve: Curves.easeOutBack);
      }).toList(),
    );
  }
}
