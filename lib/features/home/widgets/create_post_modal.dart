import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';

class CreatePostModal extends StatefulWidget {
  const CreatePostModal({super.key});

  @override
  State<CreatePostModal> createState() => _CreatePostModalState();
}

class _CreatePostModalState extends State<CreatePostModal> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<File> _selectedImages = [];
  bool _isPosting = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    final position = await LocationService().getCurrentLocation();
    if (mounted) {
      setState(() => _currentPosition = position);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        // Limit to 5 images total
        final remainingSlots = 5 - _selectedImages.length;
        if (remainingSlots > 0) {
          final imagesToAdd = images.take(remainingSlots).toList();
          setState(() {
            _selectedImages.addAll(
              imagesToAdd.map((xfile) => File(xfile.path)),
            );
          });

          if (images.length > imagesToAdd.length) {
            _showSnack('Maximum 5 images allowed');
          }
        } else {
          _showSnack('Maximum 5 images allowed');
        }
      }
    } catch (e) {
      print('Error picking images: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) {
      _showSnack('Please add some text or an image');
      return;
    }

    setState(() => _isPosting = true);

    try {
      final result = await SocialService().createPost(
        content: text,
        imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      if (result != null && mounted) {
        Navigator.pop(context, result); // Return the post data
        _showSnack('Posted! 🎉');
      } else if (mounted) {
        _showSnack('Failed to post');
      }
    } catch (e) {
      print('Error posting: $e');
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
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
                    'New Post',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton(
                  onPressed: _isPosting ? null : _post,
                  child: _isPosting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Post',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text Input
                  TextField(
                    controller: _textController,
                    maxLines: null,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: "What's on your mind?",
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),

                  // Image Preview Grid
                  if (_selectedImages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedImages.asMap().entries.map((entry) {
                        final index = entry.key;
                        final image = entry.value;
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                image,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _selectedImages.removeAt(index);
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.image_outlined,
                    color: _selectedImages.length < 5
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
                  onPressed: _selectedImages.length < 5 ? _pickImage : null,
                  tooltip: 'Add Photo',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
