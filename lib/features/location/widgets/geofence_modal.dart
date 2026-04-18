import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/core/services/checkin_service.dart';
import 'package:bitemates/features/gamification/widgets/badge_earned_overlay.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';

class GeofenceModal extends StatefulWidget {
  final Map<String, dynamic> eventData;
  final VoidCallback? onCheckIn;

  const GeofenceModal({super.key, required this.eventData, this.onCheckIn});

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> eventData,
    VoidCallback? onCheckIn,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          GeofenceModal(eventData: eventData, onCheckIn: onCheckIn),
    );
  }

  @override
  State<GeofenceModal> createState() => _GeofenceModalState();
}

class _GeofenceModalState extends State<GeofenceModal>
    with TickerProviderStateMixin {
  bool _isCheckingIn = false;

  // Pulse animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // Slide-up entry animation
  late final AnimationController _entryController;
  late final Animation<double> _entryAnim;

  String get _tableId => widget.eventData['id'] ?? '';
  String get _title => widget.eventData['title'] ?? 'Nearby Event';
  String? get _locationName => widget.eventData['location_name'];
  String? get _datetime => widget.eventData['datetime'];
  int get _currentCapacity =>
      (widget.eventData['current_capacity'] ?? 0) as int;
  int get _maxGuests => (widget.eventData['max_guests'] ?? 0) as int;
  bool get _isJoined => widget.eventData['is_joined'] == true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _entryAnim = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  String _formatTimeUntil() {
    if (_datetime == null) return '';
    try {
      final eventTime = DateTime.parse(_datetime!);
      final diff = eventTime.difference(DateTime.now());
      if (diff.isNegative) return 'Happening now 🔥';
      if (diff.inMinutes < 60) return 'In ${diff.inMinutes}m';
      if (diff.inHours < 24) return 'In ${diff.inHours}h';
      return 'In ${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleCheckIn() async {
    if (_isCheckingIn) return;
    setState(() => _isCheckingIn = true);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      final result = await CheckinService().geoCheckin(
        _tableId,
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onCheckIn?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['already'] == true
                  ? 'Already checked in! ✅'
                  : 'Checked in successfully! 🎉',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        final badges = await CheckinService().checkAndAwardBadges(
          result['user_id'] ?? '',
        );
        if (badges.isNotEmpty && mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (ctx) => BadgeEarnedOverlay(badge: badges.first),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Check-in failed'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-in error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeText = _formatTimeUntil();
    final hasCapacity = _maxGuests > 0;
    final spotsLeft = hasCapacity ? _maxGuests - _currentCapacity : 0;
    final isFull = hasCapacity && spotsLeft <= 0;
    final accentColor = _isJoined
        ? const Color(0xFF10B981) // emerald
        : const Color(0xFF4F46E5); // indigo

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(_entryAnim),
      child: FadeTransition(
        opacity: _entryAnim,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gradient header ──────────────────────────────────
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isJoined
                        ? [const Color(0xFF059669), const Color(0xFF10B981)]
                        : [const Color(0xFF3730A3), const Color(0xFF6366F1)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: Column(
                  children: [
                    // Drag handle (white on gradient)
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Animated pulse ring + icon
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer ring
                            Transform.scale(
                              scale: _pulseAnim.value * 1.3,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(
                                    0.15 * _pulseAnim.value,
                                  ),
                                ),
                              ),
                            ),
                            // Mid ring
                            Transform.scale(
                              scale: _pulseAnim.value * 1.1,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(
                                    0.2 * _pulseAnim.value,
                                  ),
                                ),
                              ),
                            ),
                            // Core circle
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.2),
                              ),
                              child: Icon(
                                _isJoined
                                    ? Icons.where_to_vote_rounded
                                    : Icons.location_on_rounded,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Headline
                    Text(
                      _isJoined ? "You've Arrived! 👋" : "You're Nearby! 📍",
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.85),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (_locationName != null &&
                        _locationName!.isNotEmpty &&
                        _locationName != _title) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _locationName!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── Body ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  children: [
                    // Info chips
                    if (timeText.isNotEmpty || hasCapacity)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (timeText.isNotEmpty)
                            _Chip(
                              icon: Icons.schedule_rounded,
                              label: timeText,
                              bgColor: const Color(0xFFFFF7ED),
                              fgColor: const Color(0xFFEA580C),
                              isDark: isDark,
                            ),
                          if (timeText.isNotEmpty && hasCapacity)
                            const SizedBox(width: 10),
                          if (hasCapacity)
                            _Chip(
                              icon: isFull
                                  ? Icons.block_rounded
                                  : Icons.people_rounded,
                              label: isFull
                                  ? 'Full'
                                  : '$spotsLeft spot${spotsLeft == 1 ? '' : 's'} left',
                              bgColor: isFull
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFF0FDF4),
                              fgColor: isFull
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF16A34A),
                              isDark: isDark,
                            ),
                        ],
                      ),

                    const SizedBox(height: 20),

                    // Check In button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_isCheckingIn || isFull)
                            ? null
                            : _handleCheckIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: accentColor.withOpacity(0.4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isCheckingIn
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isJoined
                                        ? Icons.where_to_vote_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isFull
                                        ? 'Event is Full'
                                        : _isJoined
                                        ? 'Check In Now'
                                        : 'Check In',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Snooze + Mute row
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              GeofenceEngine().snoozeGeofence(_tableId);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Snoozed for 1 hour'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.snooze_rounded,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                            label: Text(
                              'Snooze 1h',
                              style: GoogleFonts.inter(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 16,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              GeofenceEngine().muteGeofence(_tableId);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "We won't notify you about this again.",
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.volume_off_rounded,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                            label: Text(
                              "Don't ask again",
                              style: GoogleFonts.inter(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Safe area bottom padding
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;
  final bool isDark;

  const _Chip({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? fgColor.withOpacity(0.15) : bgColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
