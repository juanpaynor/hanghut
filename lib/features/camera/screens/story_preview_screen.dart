import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../widgets/story_overlay_widget.dart';

class StoryPreviewScreen extends StatefulWidget {
  final File? imageFile;
  final File? videoFile;
  final String locationName;
  final String? externalPlaceId;
  final String? tableId;
  final String? eventId;
  final String visibility;
  final String? vibeTag;
  final double latitude;
  final double longitude;
  final String city;

  const StoryPreviewScreen({
    Key? key,
    this.imageFile,
    this.videoFile,
    required this.locationName,
    this.externalPlaceId,
    this.tableId,
    this.eventId,
    required this.visibility,
    this.vibeTag,
    required this.latitude,
    required this.longitude,
    required this.city,
  }) : super(key: key);

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  bool _isUploading = false;
  final TextEditingController _captionController = TextEditingController();
  late String _currentLocationName;
  late String? _currentVibeTag;

  // Video Player specific state
  VideoPlayerController? _videoPlayerController;

  // We lock the time to when the photo was taken, not when it's uploaded
  late final String _capturedTime;

  @override
  void initState() {
    super.initState();
    _currentLocationName = widget.locationName;
    _currentVibeTag = widget.vibeTag;
    _capturedTime = DateFormat('h:mm a').format(DateTime.now());

    if (widget.videoFile != null) {
      _videoPlayerController = VideoPlayerController.file(widget.videoFile!)
        ..initialize().then((_) {
          _videoPlayerController!.setLooping(true);
          _videoPlayerController!.play();
          setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _uploadEditedBytes(Uint8List mediaBytes, bool isVideo) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final bucketName = isVideo ? 'social_videos' : 'post_images';
      final fileExtension = isVideo ? '.mp4' : '.jpg';
      final mimeType = isVideo ? 'video/mp4' : 'image/jpeg';
      final fileName =
          '${user.id}_story_${DateTime.now().millisecondsSinceEpoch}$fileExtension';

      await supabase.storage
          .from(bucketName)
          .uploadBinary(
            fileName,
            mediaBytes,
            fileOptions: FileOptions(contentType: mimeType),
          );

      final publicUrl = supabase.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      await supabase.from('posts').insert({
        'user_id': user.id,
        'image_url': isVideo ? null : publicUrl,
        'video_url': isVideo ? publicUrl : null,
        'content': _captionController.text.trim(),
        'post_type': isVideo ? 'video' : 'image',
        'is_story': true,
        'visibility': widget.visibility,
        'table_id': widget.tableId,
        'event_id': widget.eventId,
        'external_place_id': widget.externalPlaceId,
        'external_place_name': _currentLocationName,
        'vibe_tag': _currentVibeTag,
        'latitude': widget.latitude,
        'longitude': widget.longitude,
        'city': widget.city,
      });

      if (mounted) {
        Navigator.pop(context); // Pop Preview
        Navigator.pop(context); // Pop Camera
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Story posted! 🚀')));
      }
    } catch (e) {
      debugPrint('Error uploading story: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post story. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadStory() async {
    // If not edited via ProImageEditor, capture raw file
    if (widget.videoFile != null) {
      final bytes = await widget.videoFile!.readAsBytes();
      await _uploadEditedBytes(bytes, true);
    } else if (widget.imageFile != null) {
      final bytes = await widget.imageFile!.readAsBytes();
      await _uploadEditedBytes(bytes, false);
    }
  }

  void _showEditSheet() {
    // Allows user to correct GPS drift or change vibe before posting
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Location & Vibe',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Dummy list for now. In reality, this calls Google Places / Supabase venues.
              ListTile(
                leading: const Icon(Icons.location_on, color: Colors.indigo),
                title: Text('Change Location', style: GoogleFonts.inter()),
                subtitle: Text(_currentLocationName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Navigate to venue search
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. The Captured Media
          if (widget.videoFile != null &&
              _videoPlayerController != null &&
              _videoPlayerController!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoPlayerController!.value.size.width,
                  height: _videoPlayerController!.value.size.height,
                  child: VideoPlayer(_videoPlayerController!),
                ),
              ),
            )
          else if (widget.imageFile != null)
            Image.file(widget.imageFile!, fit: BoxFit.cover),

          // 2. Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (_isUploading)
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),

          // 3. The Passport Overlay Sticker
          Positioned(
            left: 16,
            bottom: 110, // Above caption box
            child: StoryOverlayWidget(
              locationName: _currentLocationName,
              timeString: _capturedTime,
              vibeTag: _currentVibeTag,
              onTap: _showEditSheet,
            ),
          ),

          // 4. Bottom Post Bar (Caption + Send)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Add a quick caption...',
                          hintStyle: TextStyle(color: Colors.black54),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _uploadStory,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        'Post',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
