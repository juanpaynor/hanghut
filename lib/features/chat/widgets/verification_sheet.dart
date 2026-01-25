import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart'; // Added

class VerificationSheet extends StatefulWidget {
  final String currentUserId;
  final String targetUserId; // If scanning someone else
  final String tableId;
  final bool isMe; // Is the user viewing their own code?

  const VerificationSheet({
    super.key,
    required this.currentUserId,
    required this.targetUserId,
    required this.tableId,
    required this.isMe, // true = Show QR, false = Show Scanner
  });

  @override
  State<VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends State<VerificationSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isScanning = false;
  MobileScannerController? _scannerController;
  Position? _currentPosition; // Added to store location

  @override
  void initState() {
    super.initState();
    // Default tab: If it's me, show 'My Code' (0). If target, show 'Scan' (1).
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isMe ? 0 : 1,
    );

    _tabController.addListener(() {
      if (_tabController.index == 1 && !_isScanning) {
        _startScanning();
      } else if (_tabController.index == 0 && _isScanning) {
        _stopScanning();
      }
    });

    if (!widget.isMe) {
      _startScanning();
    }
  }

  Future<void> _startScanning() async {
    // 1. Permission Check
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

    // 2. Get Location (High Accuracy for Verification)
    // We accept a slight delay for accuracy here as it's a security check
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      // We don't block the UI strictly here (client-side), we let the server decide or
      // we could do a pre-check if we had table coords.
      // For this implementation, we proceed to scan and send coords to RPC.

      setState(() {
        _isScanning = true;
        _currentPosition = position; // Save for RPC
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    // Reset tab if failed
    if (_tabController.index == 1) {
      _tabController.animateTo(0);
    }
  }

  void _stopScanning() {
    _scannerController?.dispose();
    setState(() {
      _isScanning = false;
      _scannerController = null;
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onQRScanned(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        _scannerController?.stop();
        await _processVerification(code);
        break;
      }
    }
  }

  Future<void> _processVerification(String scannedUserId) async {
    if (scannedUserId != widget.targetUserId) {
      _showError('Wrong user! Expected: ${widget.targetUserId}');
      _scannerController?.start();
      return;
    }

    if (_currentPosition == null) {
      _showError('Location not found. Cannot verify.');
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      // Call the Secure RPC
      final response = await supabase.rpc(
        'verify_participant',
        params: {
          'p_table_id': widget.tableId,
          'p_target_user_id': scannedUserId,
          'p_verifier_lat': _currentPosition!.latitude,
          'p_verifier_lng': _currentPosition!.longitude,
        },
      );

      if (response['success'] == true) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User Verified Successfully! 🎉'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw response['error'] ?? 'Unknown error';
      }
    } catch (e) {
      if (mounted) {
        _showError('Verification Failed: $e');
        _scannerController?.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black,
            tabs: const [
              Tab(text: 'My Code'),
              Tab(text: 'Scan Camera'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMyCodeTab(), _buildScannerTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCodeTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Show this to a verified member',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          QrImageView(
            data: widget.currentUserId, // Embedding User ID
            version: QrVersions.auto,
            size: 260.0,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              'Waiting to be scanned...',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    if (widget.isMe) {
      return const Center(child: Text("You cannot scan yourself."));
    }

    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onQRScanned),
        // Overlay guide
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
        const Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              'Align QR code within the frame',
              style: TextStyle(
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
