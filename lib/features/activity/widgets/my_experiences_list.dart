import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:bitemates/core/services/experience_service.dart';

class MyExperiencesList extends StatefulWidget {
  const MyExperiencesList({super.key});

  @override
  State<MyExperiencesList> createState() => _MyExperiencesListState();
}

class _MyExperiencesListState extends State<MyExperiencesList> {
  final ExperienceService _service = ExperienceService();
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    final bookings = await _service.getMyBookings();
    if (mounted) {
      setState(() {
        _bookings = bookings;
        _isLoading = false;
      });
    }
  }

  // Safely extract nested map
  Map<String, dynamic>? _safeMap(dynamic val) {
    if (val is Map<String, dynamic>) return val;
    if (val is Map) return Map<String, dynamic>.from(val);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.explore_outlined,
                size: 40,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Experiences Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Book an experience and it will show up here',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final upcoming = <Map<String, dynamic>>[];
    final past = <Map<String, dynamic>>[];

    for (final booking in _bookings) {
      final schedule = _safeMap(booking['schedule']);
      if (schedule != null && schedule['start_time'] != null) {
        final startTime = DateTime.parse(schedule['start_time']);
        (startTime.isAfter(now) ? upcoming : past).add(booking);
      } else {
        past.add(booking);
      }
    }

    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (upcoming.isNotEmpty) ...[
            _SectionHeader(
              title: 'Upcoming',
              count: upcoming.length,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            ...upcoming.map((b) => _buildBookingCard(b, isUpcoming: true)),
          ],
          if (past.isNotEmpty) ...[
            if (upcoming.isNotEmpty) const SizedBox(height: 28),
            _SectionHeader(
              title: 'Past',
              count: past.length,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            ...past.map((b) => _buildBookingCard(b, isUpcoming: false)),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingCard(
    Map<String, dynamic> booking, {
    required bool isUpcoming,
  }) {
    final table = _safeMap(booking['table']);
    final schedule = _safeMap(booking['schedule']);
    final host = _safeMap(table?['host']);

    final title = table?['title'] as String? ?? 'Experience';
    final venue = table?['venue_name'] as String? ?? '';
    final coverUrl = table?['cover_image_url'] as String?;
    final hostName = host?['display_name'] as String? ?? 'Host';
    final hostAvatar = host?['avatar_url'] as String?;
    final quantity = booking['quantity'] as int? ?? 1;
    final checkInStatus = booking['check_in_status'] as String? ?? 'pending';
    final totalAmount = booking['total_amount'];

    String? dateStr;
    String? timeStr;
    if (schedule != null && schedule['start_time'] != null) {
      final dt = DateTime.parse(schedule['start_time']);
      dateStr = DateFormat('EEE, MMM d').format(dt);
      timeStr = DateFormat('h:mm a').format(dt);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showBookingDetail(booking),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Image with overlay
              if (coverUrl != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: coverUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 160,
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Status badge on image
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _buildStatusBadge(isUpcoming, checkInStatus),
                    ),
                    // Date chip on image
                    if (dateStr != null)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$dateStr · $timeStr',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              else
                // No cover — show status at top
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 16),
                  child: _buildStatusBadge(isUpcoming, checkInStatus),
                ),

              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (coverUrl == null && dateStr != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 13,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$dateStr · $timeStr',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (venue.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.green[400],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              venue,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Bottom row: host + amount
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.green.withValues(alpha: 0.1),
                          backgroundImage: hostAvatar != null
                              ? NetworkImage(hostAvatar)
                              : null,
                          child: hostAvatar == null
                              ? const Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.green,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hostName,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (quantity > 1) ...[
                          Icon(
                            Icons.people_outline,
                            size: 14,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$quantity',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (totalAmount != null)
                          Text(
                            '₱${(totalAmount as num).toStringAsFixed(0)}',
                            style: TextStyle(
                              color: isUpcoming
                                  ? Colors.green[700]
                                  : Colors.grey[500],
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isUpcoming, String checkInStatus) {
    final (
      Color bgColor,
      Color fgColor,
      IconData icon,
      String label,
    ) = switch (checkInStatus) {
      'checked_in' => (
        Colors.blue,
        Colors.white,
        Icons.check_circle,
        'Checked In',
      ),
      _ when isUpcoming => (
        Colors.green,
        Colors.white,
        Icons.event_available,
        'Upcoming',
      ),
      _ => (Colors.grey[700]!, Colors.white70, Icons.history, 'Past'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingDetail(Map<String, dynamic> booking) {
    final table = _safeMap(booking['table']);
    final schedule = _safeMap(booking['schedule']);
    final host = _safeMap(table?['host']);
    final intentId = booking['id'] as String;
    final coverUrl = table?['cover_image_url'] as String?;

    String? dateStr;
    if (schedule != null && schedule['start_time'] != null) {
      final dt = DateTime.parse(schedule['start_time']);
      dateStr = DateFormat('EEEE, MMMM d, yyyy · h:mm a').format(dt);
    }

    final totalAmount = booking['total_amount'];
    final checkInStatus = booking['check_in_status'] ?? 'pending';
    final venue = table?['venue_name'] as String? ?? '';
    final hostName = host?['display_name'] as String? ?? 'Host';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Cover image
              if (coverUrl != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Title
                    Text(
                      table?['title'] ?? 'Experience',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Info chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (dateStr != null)
                          _infoChip(
                            Icons.calendar_today,
                            dateStr,
                            Colors.green,
                          ),
                        if (venue.isNotEmpty)
                          _infoChip(
                            Icons.location_on_outlined,
                            venue,
                            Colors.blue,
                          ),
                        _infoChip(Icons.person, hostName, Colors.purple),
                        if (totalAmount != null)
                          _infoChip(
                            Icons.receipt_long,
                            '₱${(totalAmount as num).toStringAsFixed(2)}',
                            Colors.orange,
                          ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // QR Code or Check-in Badge
                    if (checkInStatus == 'checked_in')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.blue,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'You\'re Checked In!',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Your Experience Pass',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Show this to the host',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: QrImageView(
                                data: intentId,
                                version: QrVersions.auto,
                                size: 200,
                                gapless: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                intentId.substring(0, 8).toUpperCase(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
