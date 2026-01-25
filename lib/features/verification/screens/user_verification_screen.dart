import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/user_verification_service.dart';

class UserVerificationScreen extends StatefulWidget {
  const UserVerificationScreen({super.key});

  @override
  State<UserVerificationScreen> createState() => _UserVerificationScreenState();
}

class _UserVerificationScreenState extends State<UserVerificationScreen> {
  final _verificationService = UserVerificationService();
  final _picker = ImagePicker();

  File? _idFront;
  File? _idBack;
  File? _selfie;

  bool _isLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _currentStatus;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await _verificationService.getVerificationStatus();
    if (mounted) {
      setState(() {
        _currentStatus = status;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (type == 'front') _idFront = File(image.path);
        if (type == 'back') _idBack = File(image.path);
        if (type == 'selfie') _selfie = File(image.path);
      });
    }
  }

  Future<void> _submit() async {
    if (_idFront == null || _idBack == null || _selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload all required photos')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await _verificationService.submitVerification(
      idFront: _idFront!,
      idBack: _idBack!,
      selfie: _selfie!,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification submitted!')),
        );
        _checkStatus(); // Reload to show pending state
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Status View
    if (_currentStatus != null) {
      final status = _currentStatus!['status'];
      Color statusColor = Colors.orange;
      IconData statusIcon = Icons.hourglass_empty;
      String title = 'Verification Pending';
      String desc =
          'Your documents are under review. This usually takes 24-48 hours.';

      if (status == 'approved') {
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        title = 'You are Verified!';
        desc = 'Thank you for verifying your identity.';
      } else if (status == 'rejected') {
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        title = 'Verification Failed';
        desc = 'Please try again. Make sure your photos are clear.';
        // Allow retry?
        // For now, just show rejected.
      }

      return Scaffold(
        appBar: AppBar(title: const Text('Identity Verification')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, size: 80, color: statusColor),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                if (status == 'rejected') ...[
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _currentStatus = null; // Reset to form
                        _idFront = null;
                        _idBack = null;
                        _selfie = null;
                      });
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Form View
    return Scaffold(
      appBar: AppBar(title: const Text('Identity Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verify your identity',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'To ensure safety in our community, we require all users to verified. Please upload photos of your Government ID and a selfie.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            _buildUploadCard('ID Document (Front)', 'front', _idFront),
            const SizedBox(height: 16),
            _buildUploadCard('ID Document (Back)', 'back', _idBack),
            const SizedBox(height: 16),
            _buildUploadCard('Take a Selfie', 'selfie', _selfie),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Submit Verification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Your data is securely stored and encrypted.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard(String title, String type, File? file) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _pickImage(type),
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                image: file != null
                    ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
                    : null,
              ),
              child: file == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to upload',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
