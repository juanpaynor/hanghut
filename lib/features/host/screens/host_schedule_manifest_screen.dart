import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/host/screens/host_booking_detail_screen.dart';
import 'package:bitemates/features/host/widgets/qr_scanner_screen.dart';

class HostScheduleManifestScreen extends StatefulWidget {
  final Map<String, dynamic> schedule;

  const HostScheduleManifestScreen({super.key, required this.schedule});

  @override
  State<HostScheduleManifestScreen> createState() =>
      _HostScheduleManifestScreenState();
}

class _HostScheduleManifestScreenState
    extends State<HostScheduleManifestScreen> {
  final HostService _hostService = HostService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _bookings = [];

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    try {
      final bookings = await _hostService.getScheduleBookings(
        widget.schedule['id'],
      );
      setState(() {
        _bookings = bookings;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load guest list: $e')),
        );
      }
    }
  }

  Future<void> _scanQRCode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (scannedCode != null && mounted) {
      // Find the booking with this ID
      final booking = _bookings
          .where((b) => b['id'] == scannedCode)
          .firstOrNull;

      if (booking != null) {
        // It's a valid ticket for THIS schedule
        _processCheckIn(booking);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid ticket or not for this schedule.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processCheckIn(Map<String, dynamic> booking) async {
    final status = booking['check_in_status'] ?? 'pending';
    if (status == 'checked_in') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest is already checked in!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await _hostService.checkInGuest(booking['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully checked in ${booking['guest_name']}!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadManifest(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-in failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final experienceName =
        widget.schedule['experience']?['title'] ?? 'Experience details';
    final startTimeStr = widget.schedule['start_time'] ?? '';
    final maxGuests = widget.schedule['max_guests'] as int? ?? 0;

    DateTime? start;
    if (startTimeStr.isNotEmpty) {
      start = DateTime.tryParse(startTimeStr);
    }

    final totalBooked = _bookings.fold<int>(
      0,
      (sum, b) => sum + (b['quantity'] as int? ?? 1),
    );

    final coverImage = widget.schedule['experience']?['image_url'] as String?;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildHeroHeader(
                  experienceName,
                  start,
                  totalBooked,
                  maxGuests,
                  coverImage,
                ),
                if (_bookings.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 24,
                      bottom: 100,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildGuestCard(_bookings[index]),
                        ),
                        childCount: _bookings.length,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null, // Disable hero transition to avoid tag collisions
        onPressed: _scanQRCode,
        backgroundColor: Colors.black87,
        elevation: 4,
        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
        label: Text(
          'Scan Guest Pass',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
    String title,
    DateTime? start,
    int booked,
    int max,
    String? imageUrl,
  ) {
    return SliverAppBar(
      expandedHeight: 280.0,
      pinned: true,
      backgroundColor: AppTheme.primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 20, right: 20),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20,
            shadows: [
              const Shadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(imageUrl, fit: BoxFit.cover)
            else
              Container(color: AppTheme.primaryColor),
            // Gradient overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
            // Info Overlay
            Positioned(
              left: 20,
              right: 20,
              bottom: 60, // Above the title
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Text(
                      '$booked / $max Booked',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (start != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('EEEE, MMM d').format(start),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('h:mm a').format(start),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_seat_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No guests booked yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your experience link to get bookings!',
            style: GoogleFonts.inter(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCard(Map<String, dynamic> booking) {
    final guestName = booking['guest_name'] ?? 'Guest';
    final quantity = booking['quantity'] as int? ?? 1;
    final status = booking['check_in_status'] ?? 'pending';

    final bool isCheckedIn = status == 'checked_in';
    final bool isNoShow = status == 'no_show';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isCheckedIn
              ? Colors.green.withOpacity(0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HostBookingDetailScreen(booking: booking),
              ),
            ).then((_) => _loadManifest());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                  child: Text(
                    guestName.isNotEmpty ? guestName[0].toUpperCase() : 'G',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guestName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.group,
                            size: 14,
                            color: Colors.indigo[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$quantity Guest${quantity > 1 ? 's' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Action Area
                if (isCheckedIn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Arrived',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isNoShow)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'No Show',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => _processCheckIn(booking),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                      elevation: 0,
                      side: BorderSide(
                        color: AppTheme.primaryColor.withOpacity(0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Check In',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
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
