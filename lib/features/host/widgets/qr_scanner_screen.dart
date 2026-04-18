import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';

/// UUID v4 pattern for QR code validation
final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _isProcessing = false;

  /// Result overlay state: null = scanning, true = valid UUID, false = invalid
  bool? _scanResult;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null) {
        setState(() => _isProcessing = true);

        // Stop camera immediately to free resources
        _controller.stop();

        // Validate QR content is a UUID (booking ID format)
        if (!_uuidRegex.hasMatch(code.trim())) {
          HapticFeedback.heavyImpact();
          if (mounted) {
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.red,
                  size: 40,
                ),
                title: Text(
                  'Invalid QR Code',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                content: Text(
                  'This doesn\'t look like a valid ticket.\nPlease scan the QR code from the guest\'s booking confirmation.',
                  style: GoogleFonts.inter(fontSize: 14),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Try Again',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _scanResult = null;
            });
            _controller.start();
          }
          return;
        }

        // Valid UUID — haptic + brief success overlay then pop
        HapticFeedback.mediumImpact();
        setState(() => _scanResult = true);
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, code.trim());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Scan Guest QR',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),

          // Custom Overlay Target
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _scanResult == null
                      ? Colors.white
                      : _scanResult == true
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  width: _scanResult == null ? 2 : 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Result overlay icon
          if (_scanResult != null)
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _scanResult == true
                      ? Colors.green.withOpacity(0.85)
                      : Colors.red.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _scanResult == true ? Icons.check : Icons.close,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),

          // Instructions
          if (_scanResult == null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Align the QR code within the frame to check in the guest.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
