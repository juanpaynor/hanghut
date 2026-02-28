import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/host/screens/create_experience_screen.dart';
import 'package:bitemates/features/host/screens/host_schedule_manifest_screen.dart';
import 'package:bitemates/features/host/screens/host_booking_detail_screen.dart';
import 'package:bitemates/features/host/screens/bank_accounts_screen.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class HostDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> partner;

  const HostDashboardScreen({super.key, required this.partner});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  final _hostService = HostService();
  int _selectedTab = 0;
  final GlobalKey<_BookingsTabState> _bookingsTabKey =
      GlobalKey<_BookingsTabState>();

  late final String _partnerId;

  @override
  void initState() {
    super.initState();
    _partnerId = widget.partner['id'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Host Mode',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.partner['business_name'] ?? 'My Host Dashboard',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: Text('Guest Mode', style: GoogleFonts.inter(fontSize: 13)),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _ExperiencesTab(
            partnerId: _partnerId,
            hostService: _hostService,
            onRefresh: () => setState(() {}),
          ),
          _SchedulesTab(partnerId: _partnerId, hostService: _hostService),
          _BookingsTab(
            key: _bookingsTabKey,
            partnerId: _partnerId,
            hostService: _hostService,
          ),
          _EarningsTab(
            partnerId: _partnerId,
            partner: widget.partner,
            hostService: _hostService,
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CreateExperienceScreen(partnerId: _partnerId),
                  ),
                );
                setState(() {}); // Refresh after creating
              },
              icon: const Icon(Icons.add),
              label: const Text('New Experience'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) {
          setState(() => _selectedTab = i);
          if (i == 2) {
            _bookingsTabKey.currentState?._fetchBookings();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Experiences',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Schedules',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }
}

// ─── Tab 1: Experiences ───────────────────────────────────────────────────────

class _ExperiencesTab extends StatelessWidget {
  final String partnerId;
  final HostService hostService;
  final VoidCallback onRefresh;

  const _ExperiencesTab({
    super.key,
    required this.partnerId,
    required this.hostService,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: hostService.getMyExperiences(partnerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final experiences = snapshot.data ?? [];
        if (experiences.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.explore_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No experiences yet',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap + to create your first experience',
                  style: GoogleFonts.inter(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: experiences.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _ExperienceCard(experience: experiences[i], onRefresh: onRefresh),
        );
      },
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  final Map<String, dynamic> experience;
  final VoidCallback onRefresh;

  const _ExperienceCard({
    super.key,
    required this.experience,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final images = (experience['images'] as List?)?.cast<String>() ?? [];
    final isVerified = experience['verified_by_hanghut'] == true;
    final price = experience['price_per_person'];
    final currency = experience['currency'] ?? 'PHP';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateExperienceScreen(
              partnerId: experience['partner_id'],
              existingExperience: experience,
            ),
          ),
        );
        onRefresh();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: images.isNotEmpty
                    ? Image.network(images.first, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image_outlined,
                          size: 40,
                          color: Colors.grey,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          experience['title'] ?? '',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      // Verification badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isVerified
                              ? Colors.green[50]
                              : Colors.orange[50],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVerified
                                  ? Icons.verified
                                  : Icons.hourglass_empty,
                              size: 12,
                              color: isVerified
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVerified ? 'Live' : 'Pending Review',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isVerified
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$currency ${price?.toStringAsFixed(0) ?? '0'} / person',
                    style: GoogleFonts.inter(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchedulesTab extends StatefulWidget {
  final String partnerId;
  final HostService hostService;

  const _SchedulesTab({required this.partnerId, required this.hostService});

  @override
  State<_SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<_SchedulesTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _allSchedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  Future<void> _fetchSchedules() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.hostService.getAllMySchedules(widget.partnerId);
      setState(() {
        _allSchedules = data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching schedules: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _allSchedules.where((s) {
      final dt = DateTime.tryParse(s['start_time'] ?? '') ?? DateTime.now();
      return isSameDay(dt, day);
    }).toList();
  }

  Future<void> _showAddSlotSheet(DateTime day) async {
    // Fetch host's experiences to select from
    final experiences = await widget.hostService.getMyExperiences(
      widget.partnerId,
    );
    if (!mounted) return;

    if (experiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an experience first.')),
      );
      return;
    }

    String? selectedTableId = experiences.first['id'] as String;
    TimeOfDay? startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay? endTime = const TimeOfDay(hour: 12, minute: 0);
    bool _isAdding = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add slot on ${DateFormat('MMM d, yyyy').format(day)}',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Experience',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedTableId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: experiences.map((exp) {
                      return DropdownMenuItem<String>(
                        value: exp['id'] as String,
                        child: Text(
                          exp['title'] ?? 'Experience Details',
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null)
                        setSheetState(() => selectedTableId = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Time',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final time = await showTimePicker(
                                  context: ctx,
                                  initialTime: startTime!,
                                );
                                if (time != null)
                                  setSheetState(() => startTime = time);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(startTime!.format(ctx)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Time',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final time = await showTimePicker(
                                  context: ctx,
                                  initialTime: endTime!,
                                );
                                if (time != null)
                                  setSheetState(() => endTime = time);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(endTime!.format(ctx)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isAdding
                          ? null
                          : () async {
                              setSheetState(() => _isAdding = true);
                              try {
                                final experience = experiences.firstWhere(
                                  (e) => e['id'] == selectedTableId,
                                );
                                final maxGuestsStr =
                                    experience['max_guests']?.toString() ?? '6';
                                final priceStr =
                                    experience['price_per_person']
                                        ?.toString() ??
                                    '0';

                                final sDateTime = DateTime(
                                  day.year,
                                  day.month,
                                  day.day,
                                  startTime!.hour,
                                  startTime!.minute,
                                );
                                final eDateTime = DateTime(
                                  day.year,
                                  day.month,
                                  day.day,
                                  endTime!.hour,
                                  endTime!.minute,
                                );

                                // Check if end time is before start time
                                if (eDateTime.isBefore(sDateTime)) {
                                  throw Exception(
                                    'End time must be after start time.',
                                  );
                                }

                                // Adding Schedule
                                await widget.hostService.addSchedule(
                                  tableId: selectedTableId!,
                                  startTime: sDateTime,
                                  endTime: eDateTime,
                                  maxGuests: int.tryParse(maxGuestsStr) ?? 6,
                                  pricePerPerson: double.tryParse(priceStr),
                                );
                                if (mounted) Navigator.pop(ctx);
                                _fetchSchedules();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to add slot: $e'),
                                      backgroundColor: Colors.red[700],
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setSheetState(() => _isAdding = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isAdding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Add Slot',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteSchedule(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete slot?'),
        content: const Text(
          'This will permanently delete this time slot. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.hostService.deleteSchedule(id);
      _fetchSchedules();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedDayEvents = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 365)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = selectedDay;
                });
              },
              eventLoader: _getEventsForDay,
              calendarStyle: CalendarStyle(
                markerDecoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: const TextStyle(color: Colors.redAccent),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
            ),
          ),
          Expanded(
            child: _selectedDay == null
                ? Center(
                    child: Text(
                      'Select a day',
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 24,
                      bottom: 80,
                    ),
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay!),
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (selectedDayEvents.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.event_busy,
                                  size: 48,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No slots scheduled.',
                                  style: GoogleFonts.inter(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...selectedDayEvents.map(
                          (s) => _ScheduleCard(
                            schedule: s,
                            onDelete: () => _deleteSchedule(s['id'] as String),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddSlotSheet(_selectedDay!),
              heroTag: null,
              backgroundColor: AppTheme.primaryColor,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Add Slot',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final Map<String, dynamic> schedule;
  final VoidCallback onDelete;

  const _ScheduleCard({
    super.key,
    required this.schedule,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final start =
        DateTime.tryParse(schedule['start_time'] ?? '') ?? DateTime.now();
    final end = DateTime.tryParse(schedule['end_time'] ?? '') ?? DateTime.now();
    final maxGuests = schedule['max_guests'] as int? ?? 0;
    final currentGuests = schedule['current_guests'] as int? ?? 0;
    final spotsLeft = maxGuests - currentGuests;
    final isFull = spotsLeft <= 0;
    final experienceName =
        schedule['experience']?['title'] ?? 'Experience Details';
    final coverImage = schedule['experience']?['image_url'] as String?;

    final capacityFill = maxGuests > 0 ? (currentGuests / maxGuests) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(left: 20),
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
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          HostScheduleManifestScreen(schedule: schedule),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 56, // Space for the thumbnail
                    right: 16,
                    top: 16,
                    bottom: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              experienceName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (currentGuests > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$currentGuests booked',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Right Side: Capacity Ring & Actions
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (currentGuests == 0)
                            IconButton(
                              onPressed: onDelete,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              tooltip: 'Delete Slot',
                            )
                          else
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    value: capacityFill,
                                    backgroundColor: Colors.grey[200],
                                    color: isFull
                                        ? Colors.red
                                        : AppTheme.primaryColor,
                                    strokeWidth: 4,
                                  ),
                                ),
                                Text(
                                  isFull ? 'Full' : '$spotsLeft',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isFull
                                        ? Colors.red
                                        : AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Image Thumbnail overlapping the card edge
          Positioned(
            left: 0,
            top: 16,
            bottom: 16,
            child: Container(
              width: 60,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                image: coverImage != null
                    ? DecorationImage(
                        image: NetworkImage(coverImage),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: coverImage == null
                  ? const Icon(Icons.explore, color: Colors.grey)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 3: Bookings ──────────────────────────────────────────────────────────

class _BookingsTab extends StatefulWidget {
  final String partnerId;
  final HostService hostService;

  const _BookingsTab({
    super.key,
    required this.partnerId,
    required this.hostService,
  });

  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> {
  int _selectedFilter = 0; // 0 = Upcoming, 1 = Past
  bool _isLoading = true;
  List<Map<String, dynamic>> _allBookings = [];

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.hostService.getMyBookings(widget.partnerId);
      if (mounted) {
        setState(() {
          _allBookings = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();

    final upcomingBookings = _allBookings.where((b) {
      final start =
          DateTime.tryParse(b['schedule']?['start_time'] ?? '') ?? now;
      return start.isAfter(now) || isSameDay(start, now);
    }).toList();

    final pastBookings = _allBookings.where((b) {
      final start =
          DateTime.tryParse(b['schedule']?['start_time'] ?? '') ?? now;
      return start.isBefore(now) && !isSameDay(start, now);
    }).toList();

    final displayBookings = _selectedFilter == 0
        ? upcomingBookings
        : pastBookings;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _buildFilterChip('Upcoming', 0),
              const SizedBox(width: 8),
              _buildFilterChip('Past', 1),
            ],
          ),
        ),
        Expanded(
          child: displayBookings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_seat_outlined,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedFilter == 0
                            ? 'No upcoming bookings'
                            : 'No past bookings',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchBookings,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16).copyWith(bottom: 80),
                    itemCount: displayBookings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _BookingCard(
                      booking: displayBookings[i],
                      onRefresh: _fetchBookings,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black87 : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.black87 : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onRefresh;

  const _BookingCard({required this.booking, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final guestName = booking['guest_name'] ?? 'Guest';
    final quantity = booking['quantity'] as int? ?? 1;
    final total = booking['total_amount'] as num? ?? 0;
    final schedule = booking['schedule'] as Map<String, dynamic>?;
    final experienceName =
        (booking['experience'] as Map<String, dynamic>?)?['title'] ??
        'Experience';
    final start = schedule != null
        ? DateTime.tryParse(schedule['start_time'] ?? '')
        : null;
    final checkInStatus = booking['check_in_status'] ?? 'pending';

    Color statusColor = Colors.grey[500]!;
    Color statusBg = Colors.grey[100]!;
    String statusText = 'Pending';

    if (checkInStatus == 'checked_in') {
      statusColor = Colors.green[700]!;
      statusBg = Colors.green[50]!;
      statusText = 'Checked In';
    } else if (checkInStatus == 'no_show') {
      statusColor = Colors.red[700]!;
      statusBg = Colors.red[50]!;
      statusText = 'No Show';
    } else if (start != null &&
        start.isBefore(DateTime.now()) &&
        !isSameDay(start, DateTime.now())) {
      statusText = 'Past';
    }

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HostBookingDetailScreen(booking: booking),
          ),
        );
        onRefresh();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Row: Avatar + Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                  child: Text(
                    guestName.isNotEmpty ? guestName[0].toUpperCase() : 'G',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              guestName,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusText,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        experienceName,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 14,
                            color: Colors.indigo[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$quantity Guests',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo[700],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '₱${total.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (start != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d • h:mm a').format(start),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[600],
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
          ],
        ),
      ),
    );
  }
}

// ─── Tab 4: Earnings ──────────────────────────────────────────────────────────

class _EarningsTab extends StatelessWidget {
  final String partnerId;
  final Map<String, dynamic> partner;
  final HostService hostService;

  const _EarningsTab({
    required this.partnerId,
    required this.partner,
    required this.hostService,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: hostService.getEarningsSummary(partnerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary =
            snapshot.data ??
            {
              'total_gross': 0.0,
              'total_fees': 0.0,
              'total_payout': 0.0,
              'transaction_count': 0,
            };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Earnings',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${(summary['total_gross'] as double).toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _EarningsStat(
                          label: 'Platform Fee',
                          value:
                              '₱${(summary['total_fees'] as double).toStringAsFixed(0)}',
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 24),
                        _EarningsStat(
                          label: 'Net Payout',
                          value:
                              '₱${(summary['total_payout'] as double).toStringAsFixed(0)}',
                          color: Colors.white,
                        ),
                        const SizedBox(width: 24),
                        _EarningsStat(
                          label: 'Bookings',
                          value: '${summary['transaction_count']}',
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Request payout button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showPayoutDialog(context, summary, partner),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Request Payout'),
                ),
              ),
              const SizedBox(height: 12),

              // Manage Payout Methods
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BankAccountsScreen(partnerId: partnerId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Manage Payout Methods'),
                ),
              ),
              const SizedBox(height: 24),

              // Payout history
              Text(
                'Payout History',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: hostService.getPayoutHistory(partnerId),
                builder: (context, payoutSnapshot) {
                  final payouts = payoutSnapshot.data ?? [];
                  if (payouts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No payouts yet',
                          style: GoogleFonts.inter(color: Colors.grey[400]),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: payouts
                        .map((p) => _PayoutHistoryItem(payout: p))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPayoutDialog(
    BuildContext context,
    Map<String, dynamic> summary,
    Map<String, dynamic> partner,
  ) async {
    final netPayout = summary['total_payout'] as double;

    if (netPayout <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No funds available to withdraw.')),
      );
      return;
    }

    // Show a loading indicator while fetching bank accounts
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final accounts = await hostService.getBankAccounts(partnerId);
    if (!context.mounted) return;
    Navigator.pop(context); // Close loader

    final primaryAcc = accounts.cast<Map<String, dynamic>?>().firstWhere(
      (acc) => acc != null && acc['is_primary'] == true,
      orElse: () => accounts.isNotEmpty ? accounts.first : null,
    );

    if (primaryAcc == null) {
      // Prompt Host to add an account first
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Missing Payout Method',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You must add a Bank Account or E-wallet to receive your earnings. Please set this up in Payout Methods.',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BankAccountsScreen(partnerId: partnerId),
                  ),
                );
              },
              child: const Text('Set Up Now'),
            ),
          ],
        ),
      );
      return;
    }

    // Proceed to standard Request Payout confirmation logic
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Request Payout',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available: ₱${netPayout.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Payout will be sent to:\n${primaryAcc['bank_name']}\n${primaryAcc['account_number']}',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // We pass the new bank account data to requestPayout
                await hostService.requestPayout(
                  partnerId: partnerId,
                  amount: netPayout,
                  channelCode: primaryAcc['bank_code'],
                  bankAccountNumber: primaryAcc['account_number'],
                  bankAccountName: primaryAcc['account_holder_name'],
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Payout request submitted! We\'ll process it within 3–5 business days.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to request payout: $e'),
                      backgroundColor: Colors.red[700],
                    ),
                  );
                }
              }
            },
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _EarningsStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _PayoutHistoryItem extends StatelessWidget {
  final Map<String, dynamic> payout;

  const _PayoutHistoryItem({required this.payout});

  @override
  Widget build(BuildContext context) {
    final status = payout['status'] as String? ?? 'pending_request';
    final amount = payout['amount'] as num? ?? 0;
    final createdAt =
        DateTime.tryParse(payout['created_at'] ?? '') ?? DateTime.now();

    final statusColor = switch (status) {
      'completed' => Colors.green[700]!,
      'rejected' => Colors.red[700]!,
      _ => Colors.orange[700]!,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₱${(amount as double).toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(createdAt),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.replaceAll('_', ' ').toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
