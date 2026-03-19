import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';

import '../services/location_inference_service.dart';
import '../widgets/story_overlay_widget.dart';
import 'story_preview_screen.dart';

class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen({Key? key}) : super(key: key);

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitializing = true;
  bool _isTakingPhoto = false;

  // Camera controls
  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  // Video Recording State
  bool _isVideoRecording = false;
  double _recordingProgress = 0.0;
  Timer? _videoTimer;
  final int _maxVideoSeconds = 10;

  // Post context state
  String _currentLocationName = "Locating...";
  InferredLocation? _inferredContext;
  String _visibility = 'public'; // 'public' or 'followers'
  String? _vibeTag;

  // Available vibe tags
  static const List<String> _vibeTags = [
    '🔥 Lit', '😌 Chill', '🍕 Foodie', '🎶 Vibes',
    '☕ Coffee', '🌅 Golden Hour', '🎉 Party', '💼 Hustle',
    '🏖️ Beach', '🌃 Night Out', '🥂 Celebrate', '📸 OOTD',
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _fetchLocationContext();
  }

  Future<void> _fetchLocationContext() async {
    try {
      final contextData =
          await LocationInferenceService.determineCurrentContext();
      if (mounted) {
        setState(() {
          _inferredContext = contextData;
          _currentLocationName = contextData.name;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocationName = "Unknown Location";
        });
      }
    }
  }

  Future<void> _initializeCamera({int? cameraIndex}) async {
    try {
      _cameras ??= await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final index = cameraIndex ?? 0;
        _currentCameraIndex = index.clamp(0, _cameras!.length - 1);

        // Dispose old controller before creating new one
        await _cameraController?.dispose();

        _cameraController = CameraController(
          _cameras![_currentCameraIndex],
          ResolutionPreset.high,
          enableAudio: true,
        );

        await _cameraController!.initialize();
        await _cameraController!.setFlashMode(_flashMode);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    if (_isVideoRecording) return;

    HapticFeedback.lightImpact();
    final nextIndex = (_currentCameraIndex + 1) % _cameras!.length;
    setState(() => _isInitializing = true);
    await _initializeCamera(cameraIndex: nextIndex);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    HapticFeedback.selectionClick();

    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };

    try {
      await _cameraController!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) {
      debugPrint('Flash mode error: $e');
    }
  }

  IconData _flashIcon() {
    return switch (_flashMode) {
      FlashMode.off => Icons.flash_off,
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always => Icons.flash_on,
      FlashMode.torch => Icons.flashlight_on,
    };
  }

  String _flashLabel() {
    return switch (_flashMode) {
      FlashMode.off => 'Off',
      FlashMode.auto => 'Auto',
      FlashMode.always => 'On',
      FlashMode.torch => 'Torch',
    };
  }

  @override
  void dispose() {
    _videoTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    if (_isTakingPhoto || _isVideoRecording) return;

    setState(() => _isTakingPhoto = true);
    HapticFeedback.mediumImpact();

    try {
      final XFile photo = await _cameraController!.takePicture();
      final Directory docDir = await getApplicationDocumentsDirectory();
      final String safePath =
          '${docDir.path}/story_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File safeImageFile = await File(photo.path).copy(safePath);

      _navigateToPreview(imageFile: safeImageFile);
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) _showErrorSnackBar('Failed to take photo.');
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    if (_isTakingPhoto || _isVideoRecording) return;

    try {
      HapticFeedback.heavyImpact();
      await _cameraController!.prepareForVideoRecording();
      await _cameraController!.startVideoRecording();

      setState(() {
        _isVideoRecording = true;
        _recordingProgress = 0.0;
      });

      // Start 10-second timer for progress bar and auto-stop
      _videoTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) return;
        setState(() {
          _recordingProgress = timer.tick / (10 * _maxVideoSeconds);
        });

        if (timer.tick >= (10 * _maxVideoSeconds)) {
          _stopVideoRecording();
        }
      });
    } catch (e) {
      debugPrint('Error starting video recording: $e');
      if (mounted) _showErrorSnackBar('Failed to start video recording.');
      setState(() {
        _isVideoRecording = false;
        _recordingProgress = 0.0;
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_isVideoRecording || _cameraController == null) return;
    _videoTimer?.cancel();

    // Prevent multiple calls
    if (!_cameraController!.value.isRecordingVideo) {
      setState(() {
        _isVideoRecording = false;
        _recordingProgress = 0.0;
      });
      return;
    }

    try {
      final XFile video = await _cameraController!.stopVideoRecording();

      setState(() {
        _isVideoRecording = false;
        _recordingProgress = 0.0;
      });

      final Directory docDir = await getApplicationDocumentsDirectory();
      final String safePath =
          '${docDir.path}/story_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final File safeVideoFile = await File(video.path).copy(safePath);

      _navigateToPreview(videoFile: safeVideoFile);
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
      if (mounted) _showErrorSnackBar('Failed to save video.');
      setState(() {
        _isVideoRecording = false;
        _recordingProgress = 0.0;
      });
    }
  }

  void _navigateToPreview({File? imageFile, File? videoFile}) {
    if (!mounted) return;

    if (imageFile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            imageFile,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
                Navigator.pop(context); // Pop editor

                // Save edited bytes to temp file
                final Directory tempDir = await getTemporaryDirectory();
                final File editedImage = await File(
                  '${tempDir.path}/edited_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                ).writeAsBytes(bytes);

                _pushToFinalPreview(imageFile: editedImage);
              },
            ),
          ),
        ),
      );
    } else if (videoFile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _VideoEditorScreen(
            videoFile: videoFile,
            onComplete: (bytes) async {
              Navigator.pop(context); // Pop editor

              final tempDir = await getTemporaryDirectory();
              
              // Get original extension so we don't accidentally save a .mov as purely .mp4
              final originalPath = videoFile.path.toLowerCase();
              String ext = '.mp4';
              if (originalPath.endsWith('.mov')) ext = '.mov';
              else if (originalPath.endsWith('.m4v')) ext = '.m4v';
              
              final editedVideo = File(
                '${tempDir.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}$ext',
              );
              await editedVideo.writeAsBytes(bytes);

              _pushToFinalPreview(videoFile: editedVideo);
            },
          ),
        ),
      );
    }
  }

  void _pushToFinalPreview({File? imageFile, File? videoFile}) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryPreviewScreen(
            imageFile: imageFile,
            videoFile: videoFile,
            locationName: _currentLocationName,
            externalPlaceId: _inferredContext?.externalPlaceId,
            tableId: _inferredContext?.tableId,
            eventId: _inferredContext?.eventId,
            visibility: _visibility,
            vibeTag: _vibeTag,
            latitude: _inferredContext?.latitude ?? 14.5547,
            longitude: _inferredContext?.longitude ?? 121.0244,
            city: _inferredContext?.city ?? 'Metro Manila',
          ),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickFromGallery() async {
    if (_isTakingPhoto || _isVideoRecording) return;

    try {
      final picker = ImagePicker();
      // Allow picking both Image & Video
      final XFile? media = await picker.pickMedia();

      if (media == null) return;

      final File file = File(media.path);

      // Detect if video by extension (simple check)
      final isVideo =
          media.path.toLowerCase().endsWith('.mp4') ||
          media.path.toLowerCase().endsWith('.mov');

      _navigateToPreview(
        imageFile: isVideo ? null : file,
        videoFile: isVideo ? file : null,
      );
    } catch (e) {
      debugPrint('Error picking from gallery: $e');
      if (mounted) _showErrorSnackBar('Failed to load media from gallery.');
    }
  }

  void _showEditOverlayBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Set the Vibe',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick a vibe tag for your story',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _vibeTags.map((tag) {
                      final isSelected = _vibeTag == tag;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _vibeTag = isSelected ? null : tag;
                          });
                          setSheetState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.indigo
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.indigo, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _currentLocationName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleVisibility() {
    setState(() {
      _visibility = _visibility == 'public' ? 'followers' : 'public';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text(
            'Cannot access camera.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // Modern 16:9 vertical camera aspect ratio fitting
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    final currentTime = DateFormat('h:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          Transform.scale(
            scale: scale,
            child: Center(child: CameraPreview(_cameraController!)),
          ),

          // 2. Top Bar (Close, Flash, Flip, and Follower Toggle)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Close button
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 8),
                // Flash toggle
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(_flashIcon(), color: Colors.white),
                    onPressed: _toggleFlash,
                    tooltip: 'Flash: ${_flashLabel()}',
                  ),
                ),
                const Spacer(),
                // Visibility toggle
                GestureDetector(
                  onTap: _toggleVisibility,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _visibility == 'public'
                          ? Colors.black45
                          : Colors.indigo,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _visibility == 'public' ? Icons.public : Icons.group,
                          color: _visibility == 'public'
                              ? Colors.white70
                              : Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _visibility == 'public'
                              ? 'Public Map'
                              : 'Followers Only',
                          style: GoogleFonts.inter(
                            color: _visibility == 'public'
                                ? Colors.white70
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. The Auto-Overlay Sticker (Bottom Left)
          Positioned(
            left: 16,
            bottom: 120, // Keep it above the camera shutter
            child: StoryOverlayWidget(
              locationName: _currentLocationName,
              timeString: currentTime,
              vibeTag: _vibeTag,
              onTap: _showEditOverlayBottomSheet,
            ),
          ),

          // 4. Camera Controls (Bottom area)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Gallery Button (Bottom Left)
                Positioned(
                  left: 24,
                  child: GestureDetector(
                    onTap: _pickFromGallery,
                    child: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                      child: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),

                // Center Shutter Button
                GestureDetector(
                  onTap: _takePhoto,
                  onLongPressStart: (_) => _startVideoRecording(),
                  onLongPressEnd: (_) => _stopVideoRecording(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Video Recording Progress Circle
                      if (_isVideoRecording)
                        SizedBox(
                          width: 86,
                          height: 86,
                          child: CircularProgressIndicator(
                            value: _recordingProgress,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.red,
                            ),
                            strokeWidth: 6,
                          ),
                        ),

                      // Base Shutter Button
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isVideoRecording
                                ? Colors.transparent
                                : Colors.white,
                            width: 4,
                          ),
                        ),
                        child: _isTakingPhoto
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              )
                            : Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: _isVideoRecording ? 40 : 64,
                                  width: _isVideoRecording ? 40 : 64,
                                  decoration: BoxDecoration(
                                    color: _isVideoRecording
                                        ? Colors.red
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      _isVideoRecording ? 8 : 32,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                // Flip Camera Button (Bottom Right)
                Positioned(
                  right: 24,
                  child: GestureDetector(
                    onTap: _flipCamera,
                    child: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                      child: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoEditorScreen extends StatefulWidget {
  final File videoFile;
  final Function(Uint8List) onComplete;

  const _VideoEditorScreen({
    Key? key,
    required this.videoFile,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<_VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<_VideoEditorScreen> {
  final _editorKey = GlobalKey<ProImageEditorState>();
  ProVideoController? _proVideoController;
  VideoPlayerController? _videoController;
  late VideoMetadata _videoMetadata;

  @override
  void initState() {
    super.initState();
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    final video = EditorVideo.file(widget.videoFile.path);
    _videoMetadata = await ProVideoEditor.instance.getMetadata(video);

    _videoController = VideoPlayerController.file(widget.videoFile);
    await _videoController!.initialize();
    _videoController!.setLooping(true);
    _videoController!.play();

    _proVideoController = ProVideoController(
      videoPlayer: _buildVideoPlayer(),
      initialResolution: _videoMetadata.resolution,
      videoDuration: _videoMetadata.duration,
      fileSize: _videoMetadata.fileSize,
    );

    _videoController!.addListener(() {
      _proVideoController?.setPlayTime(_videoController!.value.position);
    });

    if (mounted) setState(() {});
  }

  Widget _buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: _videoController!.value.size.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _generateVideo(CompleteParameters parameters) async {
    _videoController?.pause();

    try {
      if (Platform.isIOS) {
        // Skip ProVideoEditor on iOS entirely because without FFmpeg it outputs corrupted bad data (-9405)
        debugPrint('⚠️ Skipping video rendering on iOS, using raw camera video.');
        throw Exception('Skip rendering on iOS');
      }

      // Attempt rendered export (works on Android via Media3, requires FFmpeg on iOS)
      final renderData = VideoRenderData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        video: EditorVideo.file(widget.videoFile.path),
        outputFormat: VideoOutputFormat.mp4,
        imageBytes: parameters.layers.isNotEmpty ? parameters.image : null,
        blur: parameters.blur,
        colorMatrixList: parameters.colorFilters,
      );

      final Directory directory = await getTemporaryDirectory();
      final String outputPath =
          '${directory.path}/rendered_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      await ProVideoEditor.instance.renderVideoToFile(outputPath, renderData);
      final bytes = await File(outputPath).readAsBytes();
      
      // Safety check: if standard Media3/FFmpeg fallback produces empty/invalid file, throw
      if (bytes.length < 100) throw Exception('Rendered video is too small, corrupted.');
      
      debugPrint('✅ Video rendered successfully: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB');
      widget.onComplete(bytes);
    } catch (e) {
      debugPrint('⚠️ Video rendering skipped or failed: $e');
      debugPrint('🔄 Uploading raw video without edits...');
      try {
        final bytes = await widget.videoFile.readAsBytes();
        debugPrint('📹 Raw video size: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB');
        widget.onComplete(bytes);
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_proVideoController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return ProImageEditor.video(
      _proVideoController!,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onCompleteWithParameters: _generateVideo,
        onCloseEditor: (editorMode) => Navigator.pop(context),
      ),
    );
  }
}
