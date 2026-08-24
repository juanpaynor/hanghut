import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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
import 'package:bitemates/features/shared/widgets/place_search_sheet.dart';

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
  final Set<String> _selectedVibes = {};
  bool _includeLocation = true; // Privacy: user can opt out of geotagging

  // Which lower-left utility popover is open: 'flash' | 'location' | 'privacy'.
  String? _activePopover;

  // Manual location override (set when user picks via map)
  double? _customLat;
  double? _customLng;

  Future<void> _editLocation() async {
    final result = await PlaceSearchSheet.show(
      context,
      currentLat: _customLat ?? _inferredContext?.latitude,
      currentLng: _customLng ?? _inferredContext?.longitude,
    );

    if (result != null && mounted) {
      setState(() {
        _currentLocationName = result.name;
        _customLat = result.latitude;
        _customLng = result.longitude;
        _includeLocation = true;
      });
    }
  }

  // Available vibe tags
  static const List<String> _vibeTags = [
    '🔥 Lit',
    '😌 Chill',
    '🍕 Foodie',
    '🎶 Vibes',
    '☕ Coffee',
    '🌅 Golden Hour',
    '🎉 Party',
    '💼 Hustle',
    '🏖️ Beach',
    '🌃 Night Out',
    '🥂 Celebrate',
    '📸 OOTD',
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

  IconData _flashIcon() {
    return switch (_flashMode) {
      FlashMode.off => Icons.flash_off,
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always => Icons.flash_on,
      FlashMode.torch => Icons.flashlight_on,
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
      // IMPORTANT (pro_image_editor v12): the completion callback is AWAITED by
      // the editor while its "Applying changes" overlay is showing, and only
      // after it returns does the editor hide that overlay + close itself. So
      // this callback must ONLY persist the bytes — never pop or push here.
      // Throwing (or popping the editor route) mid-callback is exactly what left
      // the overlay stranded ("hangs on Applying changes"). We navigate to the
      // final preview afterwards, once the editor route has actually closed.
      var didComplete = false;
      File? editedImage;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            imageFile,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
                didComplete = true;
                try {
                  final Directory tempDir = await getTemporaryDirectory();
                  editedImage = await File(
                    '${tempDir.path}/edited_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                  ).writeAsBytes(bytes);
                } catch (e) {
                  debugPrint('❌ Saving edited image failed: $e');
                }
              },
              // v12 done-path only closes the editor when onCloseEditor is
              // provided; this also handles the cancel/back case.
              onCloseEditor: (_) => Navigator.pop(context),
            ),
          ),
        ),
      ).then((_) {
        if (!mounted) return;
        final img = editedImage;
        if (img != null) {
          _pushToFinalPreview(imageFile: img);
        } else if (didComplete) {
          _showErrorSnackBar('Could not process the image. Please try again.');
        }
      });
    } else if (videoFile != null) {
      // Same contract as the image path above: persist only inside the awaited
      // callback, then navigate after the editor route closes.
      var didComplete = false;
      File? editedVideo;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _VideoEditorScreen(
            videoFile: videoFile,
            onComplete: (bytes) async {
              didComplete = true;
              try {
                final tempDir = await getTemporaryDirectory();

                // Preserve original extension so a .mov isn't mislabeled .mp4.
                final originalPath = videoFile.path.toLowerCase();
                String ext = '.mp4';
                if (originalPath.endsWith('.mov')) {
                  ext = '.mov';
                } else if (originalPath.endsWith('.m4v')) {
                  ext = '.m4v';
                }

                final out = File(
                  '${tempDir.path}/edited_video_${DateTime.now().millisecondsSinceEpoch}$ext',
                );
                await out.writeAsBytes(bytes);
                editedVideo = out;
              } catch (e) {
                debugPrint('❌ Saving edited video failed: $e');
              }
            },
          ),
        ),
      ).then((_) {
        if (!mounted) return;
        final vid = editedVideo;
        if (vid != null) {
          _pushToFinalPreview(videoFile: vid);
        } else if (didComplete) {
          _showErrorSnackBar('Could not process the video. Please try again.');
        }
      });
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
            locationName: _includeLocation
                ? _currentLocationName
                : 'Location hidden',
            externalPlaceId: _includeLocation
                ? _inferredContext?.externalPlaceId
                : null,
            tableId: _includeLocation ? _inferredContext?.tableId : null,
            eventId: _includeLocation ? _inferredContext?.eventId : null,
            visibility: _visibility,
            vibeTag: _selectedVibes.isEmpty ? null : _selectedVibes.join(' · '),
            includeLocation: _includeLocation,
            latitude: _includeLocation
                ? (_customLat ?? _inferredContext?.latitude ?? 14.5547)
                : null,
            longitude: _includeLocation
                ? (_customLng ?? _inferredContext?.longitude ?? 121.0244)
                : null,
            city: _includeLocation
                ? (_inferredContext?.city ?? 'Metro Manila')
                : null,
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

      if (isVideo) {
        _navigateToPreview(videoFile: file);
        return;
      }

      // Album photos come at full resolution and, on iOS, often as HEIC.
      // Handing that straight to the editor makes its export ("Applying
      // changes") stall or OOM. Downscale + transcode to a manageable JPEG
      // first — mirrors what the camera capture already produces.
      final File prepared = await _prepareGalleryImage(file);
      if (!mounted) return;
      _navigateToPreview(imageFile: prepared);
    } catch (e) {
      debugPrint('Error picking from gallery: $e');
      if (mounted) _showErrorSnackBar('Failed to load media from gallery.');
    }
  }

  /// Downscale + transcode a picked album image to a JPEG the editor can
  /// export quickly. Falls back to the original file if compression fails.
  Future<File> _prepareGalleryImage(File original) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String target =
          '${tempDir.path}/story_pick_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        original.absolute.path,
        target,
        minWidth: 1920,
        minHeight: 1920,
        quality: 88,
        format: CompressFormat.jpeg, // transcodes HEIC/HEIF → JPEG
        keepExif: false, // bake in orientation, drop stale EXIF
      );
      if (result != null) return File(result.path);
    } catch (e) {
      debugPrint('Gallery image pre-process failed, using original: $e');
    }
    return original;
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
                      width: 36,
                      height: 4,
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
                      final isSelected = _selectedVibes.contains(tag);
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (isSelected) {
                              _selectedVibes.remove(tag);
                            } else {
                              _selectedVibes.add(tag);
                            }
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
                              color: isSelected ? Colors.white : Colors.black87,
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

  // ─── Story control chrome (lower-left utility stack + popovers) ───────────

  void _togglePopover(String id) {
    HapticFeedback.selectionClick();
    setState(() => _activePopover = _activePopover == id ? null : id);
  }

  Future<void> _setFlashMode(FlashMode mode) async {
    setState(() {
      _flashMode = mode;
      _activePopover = null;
    });
    try {
      await _cameraController?.setFlashMode(mode);
    } catch (e) {
      debugPrint('Flash mode error: $e');
    }
  }

  /// Map-style white rounded-square utility button. [active] fills it purple
  /// (used for Location = on, or a control whose popover is open).
  Widget _utilityButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(
          icon,
          size: 22,
          color: active ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  /// A control + its right-side popover, so the popover stays vertically
  /// aligned with (and never covers) its button.
  Widget _controlRow(String id, Widget button, List<_PopoverOption> options) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (_activePopover == id) ...[
          const SizedBox(width: 8),
          _popover(options),
        ],
      ],
    );
  }

  Widget _popover(List<_PopoverOption> options) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1),
            InkWell(
              onTap: options[i].onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                color: options[i].selected
                    ? Colors.indigo.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        options[i].label,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: options[i].selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: options[i].selected
                              ? Colors.indigo
                              : Colors.black87,
                        ),
                      ),
                    ),
                    if (options[i].selected)
                      const Icon(Icons.check, size: 18, color: Colors.indigo),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

          // 2a. Outside-tap catcher — closes any open popover. Sits below the
          // controls so Close / capture / etc. stay tappable.
          if (_activePopover != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _activePopover = null),
              ),
            ),

          // 2b. Close (upper-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // 2c. Location / overlay tag (upper-left, below the top row)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StoryOverlayWidget(
                  locationName: _currentLocationName,
                  timeString: currentTime,
                  vibeTag: _selectedVibes.isEmpty
                      ? null
                      : _selectedVibes.join(' · '),
                  onTap: _showEditOverlayBottomSheet,
                ),
                if (_includeLocation) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _editLocation,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_location_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. Utility control stack (lower-left) — Map-style buttons, each
          // opening a popover to the right.
          Positioned(
            left: 16,
            bottom: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flash → Off / On / Auto
                _controlRow(
                  'flash',
                  _utilityButton(
                    icon: _flashIcon(),
                    active: _activePopover == 'flash',
                    onTap: () => _togglePopover('flash'),
                  ),
                  [
                    _PopoverOption(
                      label: 'Off',
                      selected: _flashMode == FlashMode.off,
                      onTap: () => _setFlashMode(FlashMode.off),
                    ),
                    _PopoverOption(
                      label: 'On',
                      selected: _flashMode == FlashMode.always ||
                          _flashMode == FlashMode.torch,
                      onTap: () => _setFlashMode(FlashMode.always),
                    ),
                    _PopoverOption(
                      label: 'Auto',
                      selected: _flashMode == FlashMode.auto,
                      onTap: () => _setFlashMode(FlashMode.auto),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Location → On / Off
                _controlRow(
                  'location',
                  _utilityButton(
                    icon: _includeLocation
                        ? Icons.location_on
                        : Icons.location_off,
                    active: _includeLocation,
                    onTap: () => _togglePopover('location'),
                  ),
                  [
                    _PopoverOption(
                      label: 'On',
                      selected: _includeLocation,
                      onTap: () => setState(() {
                        _includeLocation = true;
                        _activePopover = null;
                      }),
                    ),
                    _PopoverOption(
                      label: 'Off',
                      selected: !_includeLocation,
                      onTap: () => setState(() {
                        _includeLocation = false;
                        _activePopover = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Privacy → Public / Followers
                _controlRow(
                  'privacy',
                  _utilityButton(
                    icon: _visibility == 'public' ? Icons.public : Icons.group,
                    active: _activePopover == 'privacy',
                    onTap: () => _togglePopover('privacy'),
                  ),
                  [
                    _PopoverOption(
                      label: 'Public',
                      selected: _visibility == 'public',
                      onTap: () => setState(() {
                        _visibility = 'public';
                        _activePopover = null;
                      }),
                    ),
                    _PopoverOption(
                      label: 'Followers',
                      selected: _visibility == 'followers',
                      onTap: () => setState(() {
                        _visibility = 'followers';
                        _activePopover = null;
                      }),
                    ),
                  ],
                ),
              ],
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

/// One row inside a story-control popover (Flash / Location / Privacy).
class _PopoverOption {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PopoverOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

class _VideoEditorScreen extends StatefulWidget {
  final File videoFile;
  // Awaited by the editor's completion flow, so the caller can finish writing
  // the file before the editor hides its overlay and closes.
  final Future<void> Function(Uint8List) onComplete;

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
        debugPrint(
          '⚠️ Skipping video rendering on iOS, using raw camera video.',
        );
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
      if (bytes.length < 100)
        throw Exception('Rendered video is too small, corrupted.');

      debugPrint(
        '✅ Video rendered successfully: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB',
      );
      await widget.onComplete(bytes);
    } catch (e) {
      debugPrint('⚠️ Video rendering skipped or failed: $e');
      debugPrint('🔄 Uploading raw video without edits...');
      try {
        final bytes = await widget.videoFile.readAsBytes();
        debugPrint(
          '📹 Raw video size: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB',
        );
        await widget.onComplete(bytes);
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
