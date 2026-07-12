import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:bitemates/core/services/scanner_service.dart';

/// Continuous event-ticket scanner for organizer door staff. Calls the
/// server-side `scan_ticket` RPC (authorization enforced there) and shows a
/// colour-coded result for each scan, including seat info at check-in.
class TicketScannerScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const TicketScannerScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<TicketScannerScreen> createState() => _TicketScannerScreenState();
}

enum _Outcome { valid, alreadyScanned, wrongEvent, void_, unauthorized, notFound, error }

class _TicketScannerScreenState extends State<TicketScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final ScannerService _service = ScannerService();

  // Hardware (Bluetooth/USB HID) scanner support. These act as keyboards:
  // they "type" the code then send Enter. We capture key events with a focused
  // KeyboardListener — no Bluetooth permissions or plugin needed.
  final FocusNode _hwFocus = FocusNode();
  final StringBuffer _hwBuffer = StringBuffer();

  bool _isProcessing = false;
  Map<String, dynamic>? _lastResult; // RPC payload of the last scan
  _Outcome? _lastOutcome;
  int _scannedCount = 0;

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (code != null) _processCode(code);
  }

  void _onHardwareKey(KeyEvent event) {
    // Only react while actively scanning; ignore the camera-stopped result view.
    if (_isProcessing || _lastOutcome != null) return;
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _hwBuffer.toString();
      _hwBuffer.clear();
      if (code.trim().isNotEmpty) _processCode(code);
    } else if (event.character != null && event.character!.isNotEmpty) {
      // Accumulate printable characters the scanner "types".
      _hwBuffer.write(event.character);
    }
  }

  Future<void> _processCode(String code) async {
    if (_isProcessing) return;
    if (code.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    await _controller.stop();

    final result = await _service.scanTicket(
      code: code.trim(),
      eventId: widget.eventId,
    );

    final outcome = _classify(result);
    _feedback(outcome);

    if (mounted) {
      setState(() {
        _lastResult = result;
        _lastOutcome = outcome;
        if (outcome == _Outcome.valid) _scannedCount++;
      });
    }
  }

  _Outcome _classify(Map<String, dynamic> r) {
    if (r['success'] == true) return _Outcome.valid;
    final msg = (r['message'] ?? '').toString().toLowerCase();
    if (msg.contains('already')) return _Outcome.alreadyScanned;
    if (msg.contains('wrong event')) return _Outcome.wrongEvent;
    if (msg.contains('void')) return _Outcome.void_;
    if (msg.contains('unauthorized')) return _Outcome.unauthorized;
    if (msg.contains('not found')) return _Outcome.notFound;
    return _Outcome.error;
  }

  void _feedback(_Outcome outcome) {
    if (outcome == _Outcome.valid) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _resumeScanning() async {
    _hwBuffer.clear();
    setState(() {
      _lastResult = null;
      _lastOutcome = null;
      _isProcessing = false;
    });
    await _controller.start();
    // The "Scan Next" button stole focus — give it back to the HID listener.
    if (mounted) _hwFocus.requestFocus();
  }

  @override
  void dispose() {
    _hwFocus.dispose();
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scan Tickets',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            Text(
              widget.eventTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _hwFocus,
        autofocus: true,
        onKeyEvent: _onHardwareKey,
        child: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),

          // Scan target frame (only while actively scanning)
          if (_lastOutcome == null)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          // Running count badge
          Positioned(
            top: 8,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_scannedCount checked in',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
              ),
            ),
          ),

          // Instruction (while scanning) or result card (after a scan)
          if (_lastOutcome == null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Align the guest\'s ticket QR within the frame, '
                  'or scan with a connected Bluetooth/USB scanner.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                ),
              ),
            )
          else
            _buildResultCard(),
        ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final outcome = _lastOutcome!;
    final result = _lastResult ?? {};
    final ticket = (result['ticket'] as Map?)?.cast<String, dynamic>();
    final color = _outcomeColor(outcome);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_outcomeIcon(outcome), color: color, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _outcomeTitle(outcome),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              if (ticket?['guestName'] != null) ...[
                const SizedBox(height: 14),
                _infoRow(Icons.person, ticket!['guestName'].toString()),
              ],
              if (ticket?['tier_name'] != null)
                _infoRow(Icons.local_activity, ticket!['tier_name'].toString()),
              if (ticket?['seat'] != null)
                _infoRow(Icons.event_seat, _formatSeat(ticket!['seat'])),
              if (result['details'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  result['details'].toString(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _resumeScanning,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Scan Next',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 15, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// seat_info shape = { section, row, seat, label } (team_comms #163). Web
  /// renders the prebuilt `label` everywhere, so we do too; compose from
  /// section/row/seat only as a fallback if label is ever missing.
  String _formatSeat(dynamic seat) {
    if (seat is Map) {
      final label = seat['label'];
      if (label != null && label.toString().trim().isNotEmpty) {
        return label.toString();
      }
      final parts = [seat['section'], seat['row'], seat['seat']]
          .where((p) => p != null && p.toString().isNotEmpty)
          .join(' · ');
      return parts.isEmpty ? seat.toString() : parts;
    }
    return seat.toString();
  }

  Color _outcomeColor(_Outcome o) {
    switch (o) {
      case _Outcome.valid:
        return const Color(0xFF22A06B); // green
      case _Outcome.alreadyScanned:
      case _Outcome.wrongEvent:
        return const Color(0xFFE08A00); // amber
      case _Outcome.void_:
      case _Outcome.unauthorized:
      case _Outcome.notFound:
      case _Outcome.error:
        return const Color(0xFFD23B3B); // red
    }
  }

  IconData _outcomeIcon(_Outcome o) {
    switch (o) {
      case _Outcome.valid:
        return Icons.check_circle;
      case _Outcome.alreadyScanned:
        return Icons.history;
      case _Outcome.wrongEvent:
        return Icons.event_busy;
      case _Outcome.void_:
        return Icons.block;
      case _Outcome.unauthorized:
        return Icons.lock;
      case _Outcome.notFound:
        return Icons.search_off;
      case _Outcome.error:
        return Icons.error_outline;
    }
  }

  String _outcomeTitle(_Outcome o) {
    switch (o) {
      case _Outcome.valid:
        return 'Valid Ticket';
      case _Outcome.alreadyScanned:
        return 'Already Scanned';
      case _Outcome.wrongEvent:
        return 'Wrong Event';
      case _Outcome.void_:
        return 'Ticket Void';
      case _Outcome.unauthorized:
        return 'Unauthorized';
      case _Outcome.notFound:
        return 'Ticket Not Found';
      case _Outcome.error:
        return 'Scan Error';
    }
  }
}
