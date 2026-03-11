import 'package:flutter/material.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/home/widgets/location_picker_modal.dart';

class EditPostModal extends StatefulWidget {
  final Map<String, dynamic> post;

  const EditPostModal({super.key, required this.post});

  @override
  State<EditPostModal> createState() => _EditPostModalState();
}

class _EditPostModalState extends State<EditPostModal> {
  late TextEditingController _contentController;
  bool _isSubmitting = false;
  bool _hasChanges = false;

  double? _selectedLat;
  double? _selectedLng;
  double? _postLat;
  double? _postLng;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.post['content'] ?? '',
    );
    _contentController.addListener(_onChanged);

    // Initialize location
    _postLat = widget.post['latitude'] is num
        ? (widget.post['latitude'] as num).toDouble()
        : null;
    _postLng = widget.post['longitude'] is num
        ? (widget.post['longitude'] as num).toDouble()
        : null;
    _selectedLat = _postLat;
    _selectedLng = _postLng;
  }

  void _onChanged() {
    final textChanged =
        _contentController.text != (widget.post['content'] ?? '');
    final locationChanged =
        _selectedLat != _postLat || _selectedLng != _postLng;
    final changed = textChanged || locationChanged;

    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _openLocationPicker() async {
    // Determine starting position (either post's current location or user's current device location)
    Position? startPos;
    if (_selectedLat != null && _selectedLng != null) {
      startPos = Position(
        latitude: _selectedLat!,
        longitude: _selectedLng!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    } else {
      startPos = await LocationService().getCurrentLocation();
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationPickerModal(initialPosition: startPos),
    );

    if (result != null) {
      setState(() {
        _selectedLat = result['latitude'];
        _selectedLng = result['longitude'];
      });
      _onChanged(); // Trigger change detection
    }
  }

  Future<void> _save() async {
    final newContent = _contentController.text.trim();
    if (newContent.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post cannot be empty')));
      return;
    }

    setState(() => _isSubmitting = true);

    // Only send location if it has changed
    final locationChanged =
        _selectedLat != _postLat || _selectedLng != _postLng;

    final result = await SocialService().editPost(
      postId: widget.post['id'],
      content: newContent,
      latitude: locationChanged ? _selectedLat : null,
      longitude: locationChanged ? _selectedLng : null,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (result != null) {
        Navigator.pop(context, result); // Return updated post
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show existing images/gif as read-only preview
    final imageUrls = widget.post['image_urls'] as List?;
    final gifUrl = widget.post['gif_url'] as String?;
    final hasMedia =
        (imageUrls != null && imageUrls.isNotEmpty) ||
        (gifUrl != null && gifUrl.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Edit Post',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _hasChanges && !_isSubmitting ? _save : null,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _hasChanges
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey[400],
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              // Content editor
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        minLines: 4,
                        autofocus: true,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                        decoration: InputDecoration(
                          hintText: "What's on your mind?",
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),

                      // Show existing media as read-only
                      if (hasMedia) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.photo_library,
                                size: 20,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  gifUrl != null
                                      ? 'GIF attached (cannot be changed)'
                                      : '${imageUrls!.length} image${imageUrls.length > 1 ? 's' : ''} attached (cannot be changed)',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Event indicator
                      if (widget.post['event_id'] != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event,
                                size: 20,
                                color: Colors.blue[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Event attached (cannot be changed)',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Location Picker Row
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _openLocationPicker,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: Theme.of(context).primaryColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add Location',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    Text(
                                      (_selectedLat != null)
                                          ? 'Location Selected'
                                          : 'Tap to pick location',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
