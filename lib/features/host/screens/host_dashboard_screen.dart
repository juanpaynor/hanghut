import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/host/screens/create_experience_screen.dart';
import 'package:bitemates/features/host/screens/host_schedule_manifest_screen.dart';
import 'package:bitemates/features/host/screens/host_booking_detail_screen.dart';
import 'package:bitemates/features/host/screens/bank_accounts_screen.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _ExperienceCard extends StatefulWidget {
  final Map<String, dynamic> experience;
  final VoidCallback onRefresh;

  const _ExperienceCard({
    super.key,
    required this.experience,
    required this.onRefresh,
  });

  @override
  State<_ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends State<_ExperienceCard> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Experience?'),
        content: const Text(
          'This will permanently delete this experience, all its schedules, and associated media. This cannot be undone.',
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

    if (confirm == true && mounted) {
      setState(() => _isDeleting = true);
      try {
        await HostService().deleteExperience(widget.experience['id'] as String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Experience deleted'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onRefresh();
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.showError(context, error: e, fallbackMessage: 'Unable to delete experience.');
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final experience = widget.experience;
    final images = (experience['images'] as List?)?.cast<String>() ?? [];
    final isVerified = experience['verified_by_hanghut'] == true;
    final price = experience['price_per_person'];
    final currency = experience['currency'] ?? 'PHP';

    return Opacity(
      opacity: _isDeleting ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: _isDeleting
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateExperienceScreen(
                      partnerId: experience['partner_id'],
                      existingExperience: experience,
                    ),
                  ),
                );
                widget.onRefresh();
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
                        const SizedBox(width: 4),
                        // Popup menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onSelected: (value) {
                            if (value == 'edit') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CreateExperienceScreen(
                                    partnerId: experience['partner_id'],
                                    existingExperience: experience,
                                  ),
                                ),
                              ).then((_) => widget.onRefresh());
                            } else if (value == 'delete') {
                              _confirmDelete();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
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
                                  ErrorHandler.showError(context, error: e, fallbackMessage: 'Unable to add time slot.');
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

class _EarningsTab extends StatefulWidget {
  final String partnerId;
  final Map<String, dynamic> partner;
  final HostService hostService;

  const _EarningsTab({
    required this.partnerId,
    required this.partner,
    required this.hostService,
  });

  @override
  State<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<_EarningsTab> {
  late Future<Map<String, dynamic>> _earningsFuture;

  // Pagination state for payouts
  final List<Map<String, dynamic>> _payouts = [];
  bool _payoutsLoading = true;
  bool _payoutsHasMore = true;
  static const int _pageSize = 20;

  // Pagination state for transactions
  final List<Map<String, dynamic>> _transactions = [];
  bool _transactionsLoading = true;
  bool _transactionsHasMore = true;

  // Wallet state
  Map<String, dynamic>? _walletInfo;
  bool _walletLoading = true;

  @override
  void initState() {
    super.initState();
    _earningsFuture = widget.hostService.getEarningsSummary(widget.partnerId);
    _loadPayouts();
    _loadTransactions();
    _loadWalletInfo();
  }

  Future<void> _loadWalletInfo() async {
    try {
      // Fetch both: lightweight DB info (KYC status) + real Xendit balance
      final results = await Future.wait([
        widget.hostService.getWalletInfo(widget.partnerId),
        widget.hostService.getSubaccountBalance(widget.partnerId).catchError((_) => <String, dynamic>{}),
      ]);

      final dbInfo = results[0];
      final balanceInfo = results[1];

      if (mounted) {
        setState(() {
          _walletInfo = {
            ...dbInfo,
            ...balanceInfo,
          };
          _walletLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  void _refreshEarnings() {
    setState(() {
      _earningsFuture = widget.hostService.getEarningsSummary(widget.partnerId);
      _payouts.clear();
      _payoutsHasMore = true;
      _transactions.clear();
      _transactionsHasMore = true;
      _walletLoading = true;
    });
    _loadPayouts();
    _loadTransactions();
    _loadWalletInfo();
  }

  Future<void> _loadPayouts() async {
    if (!_payoutsHasMore) return;
    setState(() => _payoutsLoading = true);
    try {
      final results = await widget.hostService.getPayoutHistory(
        widget.partnerId,
        offset: _payouts.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _payouts.addAll(results);
        _payoutsHasMore = results.length >= _pageSize;
        _payoutsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _payoutsLoading = false);
    }
  }

  Future<void> _loadTransactions() async {
    if (!_transactionsHasMore) return;
    setState(() => _transactionsLoading = true);
    try {
      final results = await widget.hostService.getTransactionHistory(
        widget.partnerId,
        offset: _transactions.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _transactions.addAll(results);
        _transactionsHasMore = results.length >= _pageSize;
        _transactionsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _transactionsLoading = false);
    }
  }

  void _showTransactionDetail(BuildContext context, Map<String, dynamic> tx) {
    final title = tx['title'] as String? ?? 'Transaction';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final grossAmount = (tx['gross_amount'] as num?)?.toDouble() ?? 0;
    final platformFee = (tx['platform_fee'] as num?)?.toDouble() ?? 0;
    final status = tx['status'] as String? ?? 'completed';
    final type = tx['type'] as String? ?? 'experience';
    final createdAt =
        DateTime.tryParse(tx['created_at'] ?? '') ?? DateTime.now();
    final intentId = tx['intent_id'] as String?;
    final isRefund = status == 'refunded' || amount < 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon + status header
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isRefund ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isRefund
                    ? Icons.undo_rounded
                    : (type == 'experience'
                        ? Icons.explore_outlined
                        : Icons.event_outlined),
                size: 28,
                color: isRefund ? Colors.red[600] : Colors.green[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isRefund ? 'Refund' : 'Earning',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isRefund ? Colors.red[600] : Colors.green[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${isRefund ? '-' : '+'}₱${amount.abs().toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isRefund ? Colors.red[700] : Colors.green[800],
              ),
            ),
            const SizedBox(height: 24),

            // Details
            _DetailRow(label: type == 'experience' ? 'Experience' : 'Event', value: title),
            _DetailRow(
              label: 'Date',
              value: DateFormat('MMM d, yyyy · h:mm a').format(createdAt),
            ),
            _DetailRow(
              label: 'Gross Amount',
              value: '₱${grossAmount.abs().toStringAsFixed(2)}',
            ),
            if (!isRefund)
              _DetailRow(
                label: 'Platform Fee',
                value: '-₱${platformFee.abs().toStringAsFixed(2)}',
              ),
            _DetailRow(
              label: isRefund ? 'Refunded' : 'Net Payout',
              value: '₱${amount.abs().toStringAsFixed(2)}',
              isBold: true,
            ),
            if (intentId != null)
              _DetailRow(
                label: 'Reference',
                value: intentId.length > 12
                    ? '${intentId.substring(0, 12)}…'
                    : intentId,
              ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _earningsFuture,
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
              'available_balance': 0.0,
              'total_withdrawn': 0.0,
              'transaction_count': 0,
            };

        final availableBalance = (summary['available_balance'] as num?)?.toDouble() ?? 0.0;
        final totalWithdrawn = (summary['total_withdrawn'] as num?)?.toDouble() ?? 0.0;

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
                      'Available Balance',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${availableBalance.toStringAsFixed(2)}',
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
                          label: 'Total Earned',
                          value:
                              '₱${(summary['total_payout'] as double).toStringAsFixed(0)}',
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 24),
                        _EarningsStat(
                          label: 'Withdrawn',
                          value:
                              '₱${totalWithdrawn.toStringAsFixed(0)}',
                          color: Colors.white70,
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
              const SizedBox(height: 16),

              // ═══ Xendit Wallet Card ═══
              if (!_walletLoading && _walletInfo != null && _walletInfo!['xendit_account_id'] != null)
                _buildWalletCard(),

              const SizedBox(height: 16),

              // Request payout button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showPayoutDialog(context, summary, widget.partner),
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
                            BankAccountsScreen(partnerId: widget.partnerId),
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
              if (_payouts.isEmpty && !_payoutsLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No payouts yet',
                      style: GoogleFonts.inter(color: Colors.grey[400]),
                    ),
                  ),
                )
              else ...[
                ...List.generate(_payouts.length, (i) =>
                  _PayoutHistoryItem(payout: _payouts[i]),
                ),
                if (_payoutsLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_payoutsHasMore)
                  Center(
                    child: TextButton(
                      onPressed: _loadPayouts,
                      child: Text(
                        'Load More',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 28),

              // Transaction history
              Text(
                'Transaction History',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              if (_transactions.isEmpty && !_transactionsLoading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No transactions yet',
                      style: GoogleFonts.inter(color: Colors.grey[400]),
                    ),
                  ),
                )
              else ...[
                ...List.generate(_transactions.length, (i) =>
                  GestureDetector(
                    onTap: () => _showTransactionDetail(context, _transactions[i]),
                    child: _TransactionHistoryItem(transaction: _transactions[i]),
                  ),
                ),
                if (_transactionsLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_transactionsHasMore)
                  Center(
                    child: TextButton(
                      onPressed: _loadTransactions,
                      child: Text(
                        'Load More',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
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
    final availableBalance = (summary['available_balance'] as num?)?.toDouble() ?? 0.0;

    if (availableBalance <= 0) {
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

    final accounts = await widget.hostService.getBankAccounts(widget.partnerId);
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
                    builder: (_) => BankAccountsScreen(partnerId: widget.partnerId),
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
              'Available: ₱${availableBalance.toStringAsFixed(2)}',
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
                await widget.hostService.requestPayout(
                  partnerId: widget.partnerId,
                  amount: availableBalance,
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
                  // Refresh the earnings card
                  _refreshEarnings();
                }
              } catch (e) {
                if (context.mounted) {
                  ErrorHandler.showError(context, error: e, fallbackMessage: 'Unable to request payout.');
                }
              }
            },
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    final accountId = _walletInfo!['xendit_account_id'] as String;
    final receivable = (_walletInfo!['platform_fee_receivable'] as num?)?.toDouble() ?? 0.0;
    final kycStatus = _walletInfo!['kyc_status'] as String? ?? 'not_started';
    final availableWallet = (_walletInfo!['available_balance'] as num?)?.toDouble() ?? 0.0;
    final pendingSettlement = (_walletInfo!['pending_settlement'] as num?)?.toDouble() ?? 0.0;

    Color kycColor;
    String kycLabel;
    IconData kycIcon;
    switch (kycStatus) {
      case 'verified':
        kycColor = Colors.green;
        kycLabel = 'Verified';
        kycIcon = Icons.verified;
        break;
      case 'submitted':
        kycColor = Colors.orange;
        kycLabel = 'Pending Review';
        kycIcon = Icons.hourglass_top;
        break;
      default:
        kycColor = Colors.grey;
        kycLabel = 'Not Started';
        kycIcon = Icons.info_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance_wallet, color: Colors.blue[700], size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xendit Wallet',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      accountId.length > 20 ? '${accountId.substring(0, 20)}...' : accountId,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              // KYC Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kycColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kycIcon, size: 13, color: kycColor),
                    const SizedBox(width: 4),
                    Text(
                      kycLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kycColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Wallet Balance
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₱${availableWallet.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              if (pendingSettlement > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Settlement',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₱${pendingSettlement.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Platform Fee Receivable
          if (receivable > 0) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber[800], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Outstanding platform fee: ₱${receivable.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Top-up button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showTopUpSheet(context),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text(
                'Top Up Wallet',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.blue[400]!),
                foregroundColor: Colors.blue[700],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTopUpSheet(BuildContext context) {
    final presets = [500.0, 1000.0, 5000.0, 10000.0];
    double? selectedAmount;
    final customController = TextEditingController();
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              24, 16, 24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Top Up Wallet',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Funds go directly to your sub-wallet for covering refunds and fees.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                // Preset amounts
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: presets.map((amt) {
                    final isSelected = selectedAmount == amt;
                    return ChoiceChip(
                      label: Text(
                        '₱${amt.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: Colors.grey[100],
                      onSelected: (_) {
                        setSheetState(() {
                          selectedAmount = amt;
                          customController.clear();
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Custom amount
                TextField(
                  controller: customController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Or enter custom amount',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      setSheetState(() => selectedAmount = parsed);
                    }
                  },
                ),
                const SizedBox(height: 24),

                // Confirm
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedAmount == null || selectedAmount! < 100 || isProcessing)
                        ? null
                        : () async {
                            setSheetState(() => isProcessing = true);
                            try {
                              final result = await widget.hostService.topUpWallet(
                                partnerId: widget.partnerId,
                                amount: selectedAmount!,
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);

                              final paymentUrl = result['payment_url'] as String?;
                              if (paymentUrl != null) {
                                final uri = Uri.parse(paymentUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              }

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Top-up link created for ₱${selectedAmount!.toStringAsFixed(0)}'),
                                    backgroundColor: Colors.green[700],
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() => isProcessing = false);
                              if (ctx.mounted) {
                                ErrorHandler.showError(ctx, error: e, fallbackMessage: 'Unable to process refund.');
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            selectedAmount != null
                                ? 'Top Up ₱${selectedAmount!.toStringAsFixed(0)}'
                                : 'Select an amount',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
                if (selectedAmount != null && selectedAmount! < 100)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Minimum top-up amount is ₱100',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.red[600]),
                    ),
                  ),
              ],
            ),
          );
        },
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

class _TransactionHistoryItem extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const _TransactionHistoryItem({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final title = transaction['title'] as String? ?? 'Transaction';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final status = transaction['status'] as String? ?? 'completed';
    final type = transaction['type'] as String? ?? 'experience';
    final createdAt =
        DateTime.tryParse(transaction['created_at'] ?? '') ?? DateTime.now();

    final isRefund = status == 'refunded' || amount < 0;
    final displayAmount = amount.abs();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRefund
              ? Colors.red.withOpacity(0.2)
              : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isRefund
                  ? Colors.red[50]
                  : Colors.green[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isRefund
                  ? Icons.undo_rounded
                  : (type == 'experience'
                      ? Icons.explore_outlined
                      : Icons.event_outlined),
              size: 18,
              color: isRefund ? Colors.red[600] : Colors.green[600],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy · h:mm a').format(createdAt),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isRefund ? '-' : '+'}₱${displayAmount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isRefund ? Colors.red[600] : Colors.green[700],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isRefund
                      ? Colors.red[50]
                      : Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isRefund ? 'REFUND' : type.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isRefund ? Colors.red[600] : Colors.green[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
