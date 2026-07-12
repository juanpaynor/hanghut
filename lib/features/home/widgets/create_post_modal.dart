import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/chat/widgets/klipy_gif_picker.dart';
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
  bool _locationEnabled = true;

  // Author (for the composer header)
  String? _authorName;
  String? _authorAvatar;

  // Mention state
  String? _mentionQuery;
  bool _showMentionOverlay = false;

  bool get _hasContent =>
      _textController.text.trim().isNotEmpty ||
      _selectedImages.isNotEmpty ||
      _selectedVideo != null ||
      _selectedGifUrl != null;

  @override
  void initState() {
    super.initState();
    _checkLocation();
    _loadAuthor();
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

  Future<void> _loadAuthor() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await SupabaseConfig.client
          .from('users')
          .select('display_name, avatar_url, user_photos(photo_url, is_primary)')
          .eq('id', uid)
          .maybeSingle();
      if (mounted && row != null) {
        // Most users have no users.avatar_url — the photo lives in user_photos
        // (primary). Prefer avatar_url, fall back to the primary/first photo.
        final photos = row['user_photos'] as List? ?? [];
        String? photo;
        if (photos.isNotEmpty) {
          final primary = photos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => photos.first,
          );
          photo = primary['photo_url'] as String?;
        }
        setState(() {
          _authorName = row['display_name'] as String?;
          _authorAvatar = (row['avatar_url'] as String?) ?? photo;
        });
      }
    } catch (_) {
      // Non-critical — header just falls back to a generic avatar.
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

    // Always rebuild so the character counter and Post-button enabled state
    // track the text live.
    setState(() {
      if (mentionMatch != null) {
        _showMentionOverlay = true;
        _mentionQuery = mentionMatch.group(1) ?? '';
      } else {
        _showMentionOverlay = false;
        _mentionQuery = null;
      }
    });
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
      final remaining = 4 - _selectedImages.length;
      if (remaining <= 0) {
        _showSnack('Maximum 4 images allowed');
        return;
      }

      final List<XFile> picked = await _picker.pickMultiImage(
        imageQuality: 90,
        limit: remaining,
      );

      if (picked.isEmpty || !mounted) return;

      // Run each image through ProImageEditor so users can crop before posting
      for (final xfile in picked) {
        if (_selectedImages.length >= 4) break;
        final cropped = await _cropWithEditor(File(xfile.path));
        if (cropped != null && mounted) {
          setState(() {
            _selectedImages.add(cropped);
            _selectedGifUrl = null;
            _clearVideo();
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  /// Opens the native crop screen so the user can crop/rotate
  /// before the image is added to the post. Returns null if cancelled.
  Future<File?> _cropWithEditor(File imageFile) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFF6B35),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Edit Photo',
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );

    if (cropped == null) return null;
    return File(cropped.path);
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
      builder: (context) => KlipyGifPicker(
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
    if (text.isEmpty &&
        _selectedImages.isEmpty &&
        _selectedVideo == null &&
        _selectedGifUrl == null) {
      _showSnack('Please add some text, image, video, or GIF');
      return;
    }

    setState(() => _isPosting = true);

    try {
      // Resolve @mentions to UUIDs (batch query, no N+1)
      List<String>? mentionedUserIds;
      final mentionedUsernames = _extractMentionedUsernames(text);
      if (mentionedUsernames.isNotEmpty) {
        final usernameToId = await SocialService().resolveUsernames(
          mentionedUsernames,
        );
        mentionedUserIds = usernameToId.values.toList();
      }

      final result = await SocialService().createPost(
        content: text,
        imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
        videoFile: _selectedVideo,
        gifUrl: _selectedGifUrl,
        latitude: _locationEnabled ? _currentPosition?.latitude : null,
        longitude: _locationEnabled ? _currentPosition?.longitude : null,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            size: 24,
            color: isDark ? Colors.grey[300] : Colors.grey[700],
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Post',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _buildPostButton()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildAuthorRow(isDark),
            ),
            Divider(
              height: 1,
              color: isDark ? Colors.grey[850] : Colors.grey[200],
            ),

            // Content
            Expanded(
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
                        hintText:
                            "What's on your mind? Use @ to mention someone",
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

                    // Media toolbar — sits right under the composer, not
                    // pinned to the screen bottom.
                    const SizedBox(height: 4),
                    _buildToolbar(
                      isDark,
                      hasImages,
                      hasVideo,
                      _textController.text.characters.length,
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
                              aspectRatio:
                                  _videoPreviewController!.value.aspectRatio,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(
                                  _videoPreviewController!.value.duration,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
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
          ],
        ),
      ),
    );
  }

  /// Post button — dimmed & inert until there's something to post.
  Widget _buildPostButton() {
    if (_isPosting) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final enabled = _hasContent;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? _post : null,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Post',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "You, posting" identity row. Audience is Public-only today (the feed RPCs
  /// don't surface 'followers' posts), so it's shown as a static label.
  Widget _buildAuthorRow(bool isDark) {
    final hasAvatar = _authorAvatar != null && _authorAvatar!.isNotEmpty;
    final initial = (_authorName != null && _authorName!.isNotEmpty)
        ? _authorName![0].toUpperCase()
        : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
          backgroundImage: hasAvatar ? NetworkImage(_authorAvatar!) : null,
          child: hasAvatar
              ? null
              : Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _authorName ?? 'You',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    'Public',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    bool isDark,
    bool hasImages,
    bool hasVideo,
    int textLen,
  ) {
    const maxLen = 500;
    final nearLimit = textLen >= maxLen - 60;
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildLocationChip(isDark),
              const Spacer(),
              if (nearLimit)
                Text(
                  '$textLen/$maxLen',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textLen > maxLen ? Colors.red : Colors.grey[500],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MediaButton(
                icon: Icons.photo_library_rounded,
                label: hasImages
                    ? '${_selectedImages.length} Photo${_selectedImages.length > 1 ? 's' : ''}'
                    : 'Photo',
                isActive: hasImages,
                onPressed: _selectedVideo == null && _selectedImages.length < 4
                    ? _pickImage
                    : null,
              ),
              const SizedBox(width: 10),
              _MediaButton(
                icon: Icons.videocam_rounded,
                label: hasVideo ? '1 Video' : 'Video',
                isActive: hasVideo,
                onPressed: !hasVideo && _selectedImages.isEmpty
                    ? _pickVideo
                    : null,
              ),
              const SizedBox(width: 10),
              _MediaButton(
                icon: Icons.gif_rounded,
                label: _selectedGifUrl != null ? '1 GIF' : 'GIF',
                isActive: _selectedGifUrl != null,
                onPressed: _selectedGifUrl == null && !hasVideo
                    ? _pickGif
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Location geotag toggle — makes the silent geotag visible & optional.
  Widget _buildLocationChip(bool isDark) {
    final hasLoc = _currentPosition != null;
    final on = _locationEnabled && hasLoc;
    return InkWell(
      onTap: hasLoc
          ? () => setState(() => _locationEnabled = !_locationEnabled)
          : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : (isDark ? Colors.grey[850] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.location_on : Icons.location_off,
              size: 15,
              color: on ? AppTheme.primaryColor : Colors.grey[500],
            ),
            const SizedBox(width: 5),
            Text(
              !hasLoc
                  ? 'Locating…'
                  : (on ? 'Location on' : 'Location off'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? AppTheme.primaryColor : Colors.grey[500],
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

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onPressed;

  const _MediaButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brand = AppTheme.primaryColor;

    Color iconColor;
    Color textColor;
    Color bgColor;

    if (isActive) {
      iconColor = Colors.white;
      textColor = Colors.white;
      bgColor = brand;
    } else if (isDisabled) {
      iconColor = isDark ? Colors.grey[700]! : Colors.grey[350]!;
      textColor = isDark ? Colors.grey[700]! : Colors.grey[350]!;
      bgColor = isDark ? Colors.grey[850]! : Colors.grey[100]!;
    } else {
      iconColor = isDark ? Colors.grey[300]! : Colors.grey[700]!;
      textColor = isDark ? Colors.grey[300]! : Colors.grey[700]!;
      bgColor = isDark ? Colors.grey[800]! : Colors.grey[100]!;
    }

    return Expanded(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
