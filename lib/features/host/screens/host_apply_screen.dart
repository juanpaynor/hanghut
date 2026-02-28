import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/host/screens/host_pending_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class HostApplyScreen extends StatefulWidget {
  const HostApplyScreen({super.key});

  @override
  State<HostApplyScreen> createState() => _HostApplyScreenState();
}

class _HostApplyScreenState extends State<HostApplyScreen> {
  final _hostService = HostService();
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step 1 — About You
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  // Step 2 — What You'll Host
  String? _selectedType;
  final _offerController = TextEditingController();

  // Step 3 — Contact
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();

  final _types = [
    ('workshop', '🎨', 'Workshop'),
    ('adventure', '🧗', 'Adventure'),
    ('food_tour', '🍜', 'Food Tour'),
    ('nightlife', '🎶', 'Nightlife'),
    ('culture', '🏛️', 'Culture'),
    ('other', '✨', 'Other'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _offerController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await _hostService.applyAsHost(
        businessName: _nameController.text.trim(),
        description: _offerController.text.trim(),
        representativeName: _nameController.text.trim(),
        contactNumber: _contactController.text.trim(),
        workEmail: _emailController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HostPendingScreen()),
        );
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

  Future<void> _openKycWeb() async {
    // TODO: Replace with actual web KYC URL
    final uri = Uri.parse('https://hanghut.com/host/apply');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Become a Host',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: List.generate(3, (i) {
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _currentStep
                          ? AppTheme.primaryColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),

          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildStep1(), _buildStep2(), _buildStep3()],
            ),
          ),

          // Bottom CTA
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
                        _currentStep < 2 ? 'Continue' : 'Submit Application',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is how guests will know you.',
            style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          _buildLabel('Your Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'e.g. Maria Santos'),
          ),
          const SizedBox(height: 20),
          _buildLabel('Host Bio'),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Tell guests what makes you a great host...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What will you host?',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the type of experience you plan to offer.',
            style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
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
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
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
                      Text(type.$2, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        type.$3,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          _buildLabel('Describe what you\'ll offer'),
          const SizedBox(height: 8),
          TextField(
            controller: _offerController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. A hands-on pottery workshop for beginners...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact & Verification',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll use this to contact you about your application.',
            style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          _buildLabel('Contact Number'),
          const SizedBox(height: 8),
          TextField(
            controller: _contactController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+63 917 123 4567'),
          ),
          const SizedBox(height: 20),
          _buildLabel('Work / Business Email'),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
          const SizedBox(height: 32),

          // KYC web redirect card
          GestureDetector(
            onTap: _openKycWeb,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Colors.blue,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Complete ID Verification',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[800],
                          ),
                        ),
                        Text(
                          'Upload your ID and bank details on the web (optional now, required before going live)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.blue[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new, color: Colors.blue[400], size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
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
