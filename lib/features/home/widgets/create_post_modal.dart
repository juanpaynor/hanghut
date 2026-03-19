import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/home/widgets/mention_overlay.dart';
import 'package:video_player/video_player.dart';

import 'dart:io';

class CreatePostModal extends StatefulWidget {
  const CreatePostModal({super.key});

  @override
  State<CreatePostModal> createState() => _CreatePostModalState();
}

class _CreatePostModalState extends State<CreatePostModal> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _textFocus = FocusNode();

  List<File> _selectedImages = [];
  File? _selectedVideo;
  VideoPlayerController? _videoPreviewController;
  String? _selectedGifUrl;
  bool _isPosting = false;
  Position? _currentPosition;

  // Mention state
  String? _mentionQuery;
  bool _showMentionOverlay = false;

  @override
  void initState() {
    super.initState();
    _checkLocation();
    _textController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
    });
  }

  Future<void> _checkLocation() async {
    final position = await LocationService().getCurrentLocation();
    if (mounted) {
      setState(() => _currentPosition = position);
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocus.dispose();
    _videoPreviewController?.dispose();
    super.dispose();
  }

  /// Detect @mention trigger while typing
  void _onTextChanged() {
    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;
    if (cursorPos < 0 || cursorPos > text.length) {
      _hideMentionOverlay();
      return;
    }

    // Look backwards from cursor for an @ that starts a mention
    final beforeCursor = text.substring(0, cursorPos);
    final mentionMatch = RegExp(r'@([a-zA-Z0-9_]*)$').firstMatch(beforeCursor);

    if (mentionMatch != null) {
      final query = mentionMatch.group(1) ?? '';
      setState(() {
        _showMentionOverlay = true;
        _mentionQuery = query;
      });
    } else {
      _hideMentionOverlay();
    }
  }

  void _hideMentionOverlay() {
    if (_showMentionOverlay) {
      setState(() {
        _showMentionOverlay = false;
        _mentionQuery = null;
      });
    }
  }

  void _onMentionSelected(Map<String, dynamic> user) {
    final username = user['username'] as String? ?? '';
    if (username.isEmpty) return;

    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;
    final beforeCursor = text.substring(0, cursorPos);

    // Find the @ that triggered this mention
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0) return;

    // Replace @partial with @username + space
    final afterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}@$username $afterCursor';
    _textController.text = newText;

    // Move cursor to after the inserted mention
    final newCursorPos = atIndex + username.length + 2; // +2 for @ and space
    _textController.selection = TextSelection.collapsed(offset: newCursorPos);

    _hideMentionOverlay();
  }

  /// Extract all @usernames from text content
  List<String> _extractMentionedUsernames(String text) {
    final regex = RegExp(r'@([a-zA-Z0-9_]+)');
    return regex.allMatches(text).map((m) => m.group(1)!).toSet().toList();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null && _selectedImages.length < 4) {
        setState(() {
          _selectedImages.add(File(image.path));
          _selectedGifUrl = null;
          _clearVideo();
        });
      } else if (_selectedImages.length >= 4) {
        _showSnack('Maximum 4 images allowed');
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        final file = File(video.path);
        final fileSize = await file.length();

        // 100MB limit
        if (fileSize > 100 * 1024 * 1024) {
          _showSnack('Video must be under 100MB');
          return;
        }

        // Initialize preview controller
        _videoPreviewController?.dispose();
        final controller = VideoPlayerController.file(file);
        await controller.initialize();

        if (mounted) {
          setState(() {
            _selectedVideo = file;
            _videoPreviewController = controller;
            _selectedImages.clear();
            _selectedGifUrl = null;
          });
        }
      }
    } catch (e) {
      print('Error picking video: $e');
      _showSnack('Failed to load video');
    }
  }

  void _clearVideo() {
    _videoPreviewController?.dispose();
    _videoPreviewController = null;
    _selectedVideo = null;
  }

  Future<void> _pickGif() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TenorGifPicker(
        onGifSelected: (gifUrl) {
          setState(() {
            _selectedGifUrl = gifUrl;
            _selectedImages.clear(); // Clear images if GIF selected
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedVideo == null && _selectedGifUrl == null) {
      _showSnack('Please add some text, image, video, or GIF');
      return;
    }

    setState(() => _isPosting = true);

    try {
      // Resolve @mentions to UUIDs (batch query, no N+1)
      List<String>? mentionedUserIds;
      final mentionedUsernames = _extractMentionedUsernames(text);
      if (mentionedUsernames.isNotEmpty) {
        final usernameToId = await SocialService().resolveUsernames(mentionedUsernames);
        mentionedUserIds = usernameToId.values.toList();
      }

      final result = await SocialService().createPost(
        content: text,
        imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
        videoFile: _selectedVideo,
        gifUrl: _selectedGifUrl,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
        mentionedUserIds: mentionedUserIds,
      );

      if (result != null && mounted) {
        Navigator.pop(context, result);
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
    final hasImages = _selectedImages.isNotEmpty;
    final hasVideo = _selectedVideo != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 600,
          minHeight: 400,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const Expanded(
                    child: Text(
                      'New Post',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _isPosting ? null : _post,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _isPosting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Post',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _textController,
                      focusNode: _textFocus,
                      maxLines: null,
                      minLines: (hasImages || hasVideo) ? 3 : 5,
                      maxLength: 500,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "What's on your mind? Use @ to mention someone",
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w400,
                        ),
                        counterText: '',
                      ),
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),

                    // Mention Overlay
                    if (_showMentionOverlay && _mentionQuery != null)
                      MentionOverlay(
                        query: _mentionQuery!,
                        onUserSelected: _onMentionSelected,
                      ),

                    // Image Preview Grid
                    if (hasImages) ...[
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
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  image,
                                  width: 90,
                                  height: 90,
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
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
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

                    // Video Preview
                    if (hasVideo && _videoPreviewController != null) ...[
                      const SizedBox(height: 16),
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: _videoPreviewController!.value.aspectRatio,
                              child: VideoPlayer(_videoPreviewController!),
                            ),
                          ),
                          // Play icon overlay
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Duration badge
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(_videoPreviewController!.value.duration),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _clearVideo();
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
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
                      ),
                    ],

                    // GIF Preview
                    if (_selectedGifUrl != null) ...[
                      const SizedBox(height: 16),
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _selectedGifUrl!,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedGifUrl = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
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
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  _ActionButton(
                    icon: Icons.image_outlined,
                    label: 'Photo',
                    color: Theme.of(context).primaryColor,
                    onPressed: _selectedVideo == null && _selectedImages.length < 4 ? _pickImage : null,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: Icons.videocam_outlined,
                    label: hasVideo ? '1 Video' : 'Video',
                    color: Colors.red[500]!,
                    onPressed: !hasVideo && _selectedImages.isEmpty ? _pickVideo : null,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: Icons.gif_box_outlined,
                    label: _selectedGifUrl != null ? '1 GIF' : 'GIF',
                    color: Colors.orange[600]!,
                    onPressed: _selectedGifUrl == null && !hasVideo ? _pickGif : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;

    final finalColor = isDisabled ? Colors.grey[400] : color;
    final bgColor = isDisabled ? Colors.grey[100] : color.withOpacity(0.1);
    final borderColor = isDisabled ? Colors.grey[300]! : color.withOpacity(0.3);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: finalColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: finalColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
