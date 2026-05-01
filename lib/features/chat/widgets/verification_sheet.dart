import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Secret used to sign QR payloads — should match across all clients.
/// Using a constant here since this is client-side validation only;
/// the real security is the server-side RPC check.
const _qrSecret = 'bitemates_verify_2026';

class VerificationSheet extends StatefulWidget {
  final String currentUserId;
  final String? targetUserId; // Nullable in batch mode
  final String tableId;
  final bool isMe; // true = show QR, false = show scanner
  final bool isHost; // true = batch scanning mode
  final List<Map<String, dynamic>> participants; // For batch mode member list

  const VerificationSheet({
    super.key,
    required this.currentUserId,
    this.targetUserId,
    required this.tableId,
    required this.isMe,
    this.isHost = false,
    this.participants = const [],
  });

  @override
  State<VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends State<VerificationSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isScanning = false;
  MobileScannerController? _scannerController;
  Position? _currentPosition;

  // Debounce: prevent multiple simultaneous scan RPC calls
  bool _isProcessing = false;

  // In-sheet feedback banner
  String? _feedbackMessage;
  bool _feedbackIsError = true;

  // Batch mode state
  final Set<String> _verifiedUserIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.isHost ? 1 : 2, // Host only sees scanner
      vsync: this,
      initialIndex: 0,
    );

    if (!widget.isMe || widget.isHost) {
      _startScanning();
    }
  }

  /// Generate a signed QR payload: hanghut:verify:{tableId}:{userId}:{hmac}
  static String generateQrPayload(String tableId, String userId) {
    final data = 'hanghut:verify:$tableId:$userId';
    final hmac = Hmac(sha256, utf8.encode(_qrSecret));
    final digest = hmac.convert(utf8.encode(data));
    return '$data:${digest.toString().substring(0, 16)}';
  }

  /// Validate and parse a QR payload
  static Map<String, String>? parseQrPayload(String raw) {
    final parts = raw.split(':');
    if (parts.length != 5) return null;
    if (parts[0] != 'hanghut' || parts[1] != 'verify') return null;

    final tableId = parts[2];
    final userId = parts[3];
    final providedHmac = parts[4];

    // Verify HMAC
    final data = 'hanghut:verify:$tableId:$userId';
    final hmac = Hmac(sha256, utf8.encode(_qrSecret));
    final expectedDigest = hmac.convert(utf8.encode(data));
    final expectedHmac = expectedDigest.toString().substring(0, 16);

    if (providedHmac != expectedHmac) return null;

    return {'tableId': tableId, 'userId': userId};
  }

  Future<void> _startScanning() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Location permission needed for verification.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showError('Location permanently denied. Enable in settings.');
      return;
    }

    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        // GPS timed out or failed — use last known as fallback
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _showError('Could not determine your location. Please try again.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _isScanning = true;
        _currentPosition = position;
        _scannerController = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      });
    } catch (e) {
      _showError('Could not get location: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _feedbackMessage = msg;
      _feedbackIsError = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _feedbackMessage == msg) {
        setState(() => _feedbackMessage = null);
      }
    });
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    setState(() {
      _feedbackMessage = msg;
      _feedbackIsError = false;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _feedbackMessage == msg) {
        setState(() => _feedbackMessage = null);
      }
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onQRScanned(BarcodeCapture capture) async {
    if (_isProcessing) return; // debounce — ignore while RPC is in flight
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        _isProcessing = true;
        _scannerController?.stop();
        await _processVerification(code);
        break;
      }
    }
  }

  Future<void> _processVerification(String raw) async {
    // Parse the signed QR payload
    final parsed = parseQrPayload(raw);

    if (parsed == null) {
      // Fallback: try treating it as a bare UUID (legacy QR codes)
      if (raw.length == 36 && raw.contains('-')) {
        await _verifyUser(raw);
        return;
      }
      _showError('Invalid QR code. Not a valid verification code.');
      _isProcessing = false;
      _scannerController?.start();
      return;
    }

    // Validate table ID matches
    if (parsed['tableId'] != widget.tableId) {
      _showError('This QR belongs to a different activity.');
      _isProcessing = false;
      _scannerController?.start();
      return;
    }

    await _verifyUser(parsed['userId']!);
  }

  Future<void> _verifyUser(String userId) async {
    // In non-batch mode, check targetUserId
    if (!widget.isHost && widget.targetUserId != null) {
      if (userId != widget.targetUserId) {
        _showError('Wrong user! Expected someone else.');
        _isProcessing = false;
        _scannerController?.start();
        return;
      }
    }

    // Skip if already verified in batch mode
    if (widget.isHost && _verifiedUserIds.contains(userId)) {
      _showError('Already scanned this member!');
      _isProcessing = false;
      _scannerController?.start();
      return;
    }

    if (_currentPosition == null) {
      _showError('Location not found. Cannot verify.');
      _isProcessing = false;
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.rpc(
        'verify_participant',
        params: {
          'p_table_id': widget.tableId,
          'p_target_user_id': userId,
          'p_verifier_lat': _currentPosition!.latitude,
          'p_verifier_lng': _currentPosition!.longitude,
        },
      );

      if (response['success'] == true) {
        HapticFeedback.heavyImpact();

        if (widget.isHost) {
          // Batch mode: mark as verified and continue scanning
          setState(() => _verifiedUserIds.add(userId));

          final name = _getParticipantName(userId);
          _showSuccess('$name verified! ✅');

          // Check if all done
          final unverifiedCount = widget.participants
              .where(
                (p) =>
                    p['userId'] != widget.currentUserId &&
                    !_verifiedUserIds.contains(p['userId']),
              )
              .length;

          if (unverifiedCount == 0) {
            // All done! Show completion
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              Navigator.pop(context, true);
            }
            return;
          }

          // Resume scanning for next person
          _isProcessing = false;
          _scannerController?.start();
        } else {
          // Single mode: close sheet
          if (mounted) {
            Navigator.pop(context, true);
            _showSuccess('User Verified Successfully! 🎉');
          }
        }
      } else {
        throw response['error'] ?? 'Unknown error';
      }
    } catch (e) {
      if (mounted) {
        _showError('Verification Failed: $e');
        _isProcessing = false;
        _scannerController?.start();
      }
    }
  }

  String _getParticipantName(String userId) {
    final match = widget.participants.where((p) => p['userId'] == userId);
    if (match.isNotEmpty) {
      return match.first['displayName'] ?? 'User';
    }
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (widget.isHost) ...[
                // Host batch mode header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verify Members',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${_verifiedUserIds.length}/${widget.participants.length - 1} scanned',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),

                // Member list with scan status
                _buildMemberList(isDark),

                const Divider(height: 1),

                // Scanner area
                Expanded(child: _buildScannerView()),
              ] else ...[
                // Standard mode with tabs
                TabBar(
                  controller: _tabController,
                  labelColor: isDark ? Colors.white : Colors.black,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: isDark ? Colors.white : Colors.black,
                  tabs: const [
                    Tab(text: 'My Code'),
                    Tab(text: 'Scan Camera'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildMyCodeTab(isDark), _buildScannerView()],
                  ),
                ),
              ],
            ],
          ), // Column
          // Floating feedback banner — always visible over scanner & QR
          if (_feedbackMessage != null)
            Positioned(
              top: 20,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _feedbackIsError
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _feedbackIsError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _feedbackMessage!,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _feedbackMessage = null),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ], // Stack children
      ),
    );
  }

  Widget _buildMemberList(bool isDark) {
    final otherMembers = widget.participants
        .where((p) => p['userId'] != widget.currentUserId)
        .toList();

    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: otherMembers.length,
        itemBuilder: (context, index) {
          final p = otherMembers[index];
          final isVerified = _verifiedUserIds.contains(p['userId']);

          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isVerified
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade300,
                          width: 2.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: isDark
                            ? Colors.grey[700]
                            : Colors.grey[200],
                        backgroundImage: p['photoUrl'] != null
                            ? CachedNetworkImageProvider(p['photoUrl'])
                            : null,
                        child: p['photoUrl'] == null
                            ? Text(
                                (p['displayName'] ?? '?')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(fontSize: 14),
                              )
                            : null,
                      ),
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (p['displayName'] ?? '?').split(' ').first,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isVerified ? const Color(0xFF10B981) : null,
                    fontWeight: isVerified ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMyCodeTab(bool isDark) {
    final qrData = generateQrPayload(widget.tableId, widget.currentUserId);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Show this to the host for verification',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 240.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange.shade600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting to be scanned...',
                  style: GoogleFonts.inter(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    if (widget.isMe && !widget.isHost) {
      return const Center(child: Text("You cannot scan yourself."));
    }

    if (!_isScanning || _scannerController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Getting your location...',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onQRScanned),
        // Scan frame overlay
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        // Bottom instruction
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.isHost
                    ? 'Scan member QR codes to verify'
                    : 'Align QR code within the frame',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        // Batch counter (host mode)
        if (widget.isHost)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_verifiedUserIds.length}/${widget.participants.length - 1} verified',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
