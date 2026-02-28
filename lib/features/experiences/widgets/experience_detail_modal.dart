import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/experience_service.dart';
import 'package:bitemates/features/experiences/screens/experience_checkout_screen.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';

class ExperienceDetailModal extends StatefulWidget {
  final Map<String, dynamic> experience;
  final Map<String, dynamic> matchData;

  const ExperienceDetailModal({
    super.key,
    required this.experience,
    required this.matchData,
  });

  @override
  State<ExperienceDetailModal> createState() => _ExperienceDetailModalState();
}

class _ExperienceDetailModalState extends State<ExperienceDetailModal> {
  final _experienceService = ExperienceService();

  List<Map<String, dynamic>> _schedules = [];
  bool _isLoadingSchedules = true;
  bool _isBooking = false;

  Map<String, dynamic>? _selectedSchedule;
  int _guestCount = 1;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchSchedules() async {
    try {
      final schedules = await _experienceService.getSchedules(
        widget.experience['id'],
      );
      if (mounted) {
        setState(() {
          _schedules = schedules;
          _isLoadingSchedules = false;
        });
      }
    } catch (e) {
      print('Error fetching schedules: $e');
      if (mounted) {
        setState(() => _isLoadingSchedules = false);
      }
    }
  }

  void _handleBookNow() {
    if (_selectedSchedule == null) {
      _showSchedulePicker(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExperienceCheckoutScreen(
          experience: widget.experience,
          schedule: _selectedSchedule!,
          quantity: _guestCount,
          unitPrice: widget.experience['price_per_person'] != null
              ? (widget.experience['price_per_person'] as num).toDouble()
              : 0.0,
        ),
      ),
    );
  }

  bool _isCreatingChat = false;

  Future<void> _messageHost(String hostId, String experienceTitle) async {
    if (_isCreatingChat) return;
    setState(() => _isCreatingChat = true);

    try {
      final chatId = await DirectChatService().startConversation(hostId);
      if (mounted) {
        Navigator.pop(context); // Close the modal
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              tableId: chatId,
              tableTitle: 'Host of $experienceTitle',
              channelId: 'dm:$chatId',
              chatType: 'dm',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract Data
    final String title = widget.experience['title'] ?? 'Untitled Experience';
    final String locationName =
        widget.experience['venue_name'] ?? 'Unknown Location';
    final String description =
        widget.experience['description'] ?? 'No description provided.';
    final double price =
        (widget.experience['price_per_person'] as num?)?.toDouble() ?? 0.0;
    final String currency = widget.experience['currency'] ?? 'PHP';

    // Media and Features
    final List<dynamic> rawImages = widget.experience['images'] ?? [];
    if (rawImages.isEmpty && widget.experience['marker_image_url'] != null) {
      rawImages.add(widget.experience['marker_image_url']);
    }

    // Helper to ensure we request high-res images (stripping w=200 etc if present)
    // We also append a dummy parameter `hq=true` to break Flutter's Image.network cache,
    // which might be serving the low-res thumbnail cached by the map markers.
    String _getHighResImageUrl(String url) {
      String newUrl = url;
      if (newUrl.contains('unsplash.com')) {
        // Unsplash: replace width and quality
        newUrl = newUrl
            .replaceAll(RegExp(r'&w=\d+'), '&w=1200')
            .replaceAll(RegExp(r'&q=\d+'), '&q=90');
      }

      // Append dummy param to bust Image.network cache
      if (newUrl.contains('?')) {
        newUrl += '&hq=true';
      } else {
        newUrl += '?hq=true';
      }
      return newUrl;
    }

    final List<String> images = rawImages
        .map((e) => _getHighResImageUrl(e.toString()))
        .toList();

    final List<dynamic> includedItems =
        widget.experience['included_items'] ?? [];
    final List<dynamic> requirements = widget.experience['requirements'] ?? [];

    final String experienceType =
        widget.experience['experience_type'] ?? 'Experience';

    // Host Fields
    final bool isVerified = widget.experience['verified_by_hanghut'] ?? false;
    final String hostName = widget.experience['host_name'] ?? 'The Host';
    final String hostId = widget.experience['host_id'] ?? '';
    final String? hostAvatar = widget.experience['host_photo_url'];
    final String hostBio = widget.experience['host_bio'] ?? '';
    final double trustScore =
        (widget.experience['host_trust_score'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. DYNAMIC IMAGE CAROUSEL
              SliverAppBar(
                expandedHeight: 400,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.white,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (images.isNotEmpty)
                        PageView.builder(
                          itemCount: images.length,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemBuilder: (context, index) {
                            return Image.network(
                              images[index],
                              fit: BoxFit.cover,
                            );
                          },
                        )
                      else
                        Container(color: Colors.grey[200]),

                      // Gradient Overlay for text readability
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 120,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Image Pagination Dots
                      if (images.length > 1)
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              images.length,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: _currentImageIndex == index ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _currentImageIndex == index
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Badges
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                experienceType.toUpperCase(),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified,
                                      color: Colors.blue,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Verified',
                                      style: GoogleFonts.inter(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. CONTENT
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TITLE & LOCATION
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 18,
                            color: Colors.pink[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              locationName,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // HOST PROFILE
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundImage: hostAvatar != null
                                      ? NetworkImage(hostAvatar)
                                      : null,
                                  backgroundColor: Colors.indigo[100],
                                  child: hostAvatar == null
                                      ? Text(
                                          hostName[0],
                                          style: const TextStyle(
                                            fontSize: 24,
                                            color: Colors.indigo,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hosted by $hostName',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      if (trustScore > 0)
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.star,
                                              color: Colors.amber,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${trustScore.toStringAsFixed(1)} Trust Score',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                if (hostId.isNotEmpty &&
                                    hostId !=
                                        SupabaseConfig
                                            .client
                                            .auth
                                            .currentUser
                                            ?.id)
                                  _isCreatingChat
                                      ? const Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          onPressed: () =>
                                              _messageHost(hostId, title),
                                          icon: const Icon(
                                            Icons.chat_bubble_outline,
                                          ),
                                          color: Colors.black87,
                                          tooltip: 'Message Host',
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            side: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                        ),
                              ],
                            ),
                            if (hostBio.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                hostBio,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                      const Divider(height: 1),
                      const SizedBox(height: 32),

                      // DESCRIPTION
                      Text(
                        'What you\'ll do',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        description,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          height: 1.6,
                          color: Colors.black87,
                        ),
                      ),

                      if (includedItems.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const Divider(height: 1),
                        const SizedBox(height: 32),
                        Text(
                          'What\'s included',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...includedItems
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.toString(),
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          height: 1.4,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ],

                      if (requirements.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const Divider(height: 1),
                        const SizedBox(height: 32),
                        Text(
                          'Things to know',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...requirements
                            .map(
                              (req) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.grey[600],
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        req.toString(),
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          height: 1.4,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ],

                      // Location info (map is shown behind this sheet)
                      if (widget.experience['location_lat'] != null &&
                          widget.experience['location_lng'] != null) ...[
                        const SizedBox(height: 32),
                        const Divider(height: 1),
                        Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              color: Colors.pink[600],
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Close window to see route on map',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('View on Map'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 20,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                      const Divider(height: 1),
                      const SizedBox(height: 32),

                      // SELECTION STATE UI
                      if (_selectedSchedule != null) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Your Selection',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo[900],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _showSchedulePicker(context),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.indigo,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Change'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_today,
                                      color: Colors.indigo,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat(
                                            'EEEE, MMMM d, y at h:mm a',
                                          ).format(
                                            DateTime.parse(
                                              _selectedSchedule!['start_time'],
                                            ).toLocal(),
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: Colors.indigo[900],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Guests',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo[900],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          onPressed: _guestCount > 1
                                              ? () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() => _guestCount--);
                                                }
                                              : null,
                                          icon: const Icon(Icons.remove),
                                          color: Colors.indigo,
                                          iconSize: 20,
                                        ),
                                        SizedBox(
                                          width: 30,
                                          child: Text(
                                            '$_guestCount',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed:
                                              _guestCount <
                                                  ((_selectedSchedule!['max_guests']
                                                          as int) -
                                                      (_selectedSchedule!['current_guests']
                                                          as int))
                                              ? () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() => _guestCount++);
                                                }
                                              : null,
                                          icon: const Icon(Icons.add),
                                          color: Colors.indigo,
                                          iconSize: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 120), // Spacing for bottom bar
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 3. FLOATING BOTTOM BAR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedSchedule != null
                              ? '$currency ${(price * _guestCount).toStringAsFixed(0)}'
                              : '$currency ${price.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          _selectedSchedule != null
                              ? 'Total for $_guestCount guests'
                              : 'per person',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isBooking ? null : _handleBookNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isBooking
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _selectedSchedule == null
                                    ? 'Check Availability'
                                    : 'Reserve',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSchedulePicker(BuildContext context) async {
    final selectedSchedule = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SchedulePickerSheet(
        schedules: _schedules,
        isLoading: _isLoadingSchedules,
      ),
    );

    if (selectedSchedule != null && mounted) {
      setState(() {
        _selectedSchedule = selectedSchedule;
        _guestCount = 1; // Reset count
      });
    }
  }
}

class _SchedulePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> schedules;
  final bool isLoading;

  const _SchedulePickerSheet({
    required this.schedules,
    required this.isLoading,
  });

  @override
  State<_SchedulePickerSheet> createState() => _SchedulePickerSheetState();
}

class _SchedulePickerSheetState extends State<_SchedulePickerSheet> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    // Filter schedules for selected day
    final schedulesForSelectedDay = widget.schedules.where((s) {
      final start = DateTime.parse(s['start_time']).toLocal();
      return _isSameDay(start, _selectedDay);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select a Date',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // CALENDAR
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TableCalendar(
                      firstDay: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                      },
                      calendarStyle: CalendarStyle(
                        selectedDecoration: BoxDecoration(
                          color: Colors.pink[600],
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.pink[100],
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      eventLoader: (day) {
                        // Return a marker if there are schedules on this day
                        return widget.schedules.where((s) {
                          final start = DateTime.parse(
                            s['start_time'],
                          ).toLocal();
                          return _isSameDay(start, day);
                        }).toList();
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // TIME SLOTS FOR SELECTED DAY
                  Text(
                    _selectedDay != null
                        ? DateFormat('EEEE, MMMM d').format(_selectedDay!)
                        : 'Timeslots',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (widget.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (schedulesForSelectedDay.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No available timeslots for this date.',
                          style: GoogleFonts.inter(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  else
                    ...schedulesForSelectedDay.map((schedule) {
                      final start = DateTime.parse(
                        schedule['start_time'],
                      ).toLocal();
                      final maxGuests = schedule['max_guests'] as int;
                      final currentGuests = schedule['current_guests'] as int;
                      final spotsLeft = maxGuests - currentGuests;
                      final isFull = spotsLeft <= 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isFull
                                ? Colors.grey[200]!
                                : Colors.pink[100]!,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: isFull ? Colors.grey[50] : Colors.white,
                        ),
                        child: ListTile(
                          enabled: !isFull,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          title: Text(
                            DateFormat('h:mm a').format(start),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isFull ? Colors.grey : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            isFull ? 'Sold Out' : '$spotsLeft spots left',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isFull ? Colors.red : Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: isFull
                              ? null
                              : ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(context, schedule),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.pink[50],
                                    foregroundColor: Colors.pink[700],
                                    elevation: 0,
                                  ),
                                  child: const Text('Select'),
                                ),
                          onTap: isFull
                              ? null
                              : () => Navigator.pop(context, schedule),
                        ),
                      );
                    }).toList(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
