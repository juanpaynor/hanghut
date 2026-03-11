import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';

class GeofenceModal extends StatelessWidget {
  final Map<String, dynamic> eventData;
  final VoidCallback? onCheckIn;

  const GeofenceModal({
    super.key,
    required this.eventData,
    this.onCheckIn,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> eventData,
    VoidCallback? onCheckIn,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GeofenceModal(
        eventData: eventData,
        onCheckIn: onCheckIn,
      ),
    );
  }

  String get _tableId => eventData['id'] ?? '';
  String get _title => eventData['title'] ?? 'Nearby Event';
  String? get _locationName => eventData['location_name'];
  String? get _datetime => eventData['datetime'];
  int get _currentCapacity => (eventData['current_capacity'] ?? 0) as int;
  int get _maxGuests => (eventData['max_guests'] ?? 0) as int;

  String _formatTimeUntil() {
    if (_datetime == null) return '';
    try {
      final eventTime = DateTime.parse(_datetime!);
      final diff = eventTime.difference(DateTime.now());

      if (diff.isNegative) return 'Happening now';
      if (diff.inMinutes < 60) return 'Starts in ${diff.inMinutes}m';
      if (diff.inHours < 24) return 'Starts in ${diff.inHours}h';
      return 'Starts in ${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeText = _formatTimeUntil();
    final hasCapacity = _maxGuests > 0;
    final spotsLeft = hasCapacity ? _maxGuests - _currentCapacity : 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Pulsing location icon
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.place_rounded,
                  size: 36,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            "You're near $_title!",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          Text(
            _locationName ?? "Would you like to check in?",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),

          // Info chips row
          if (timeText.isNotEmpty || hasCapacity)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (timeText.isNotEmpty)
                  _InfoChip(
                    icon: Icons.schedule,
                    text: timeText,
                    color: Colors.orange,
                  ),
                if (timeText.isNotEmpty && hasCapacity)
                  const SizedBox(width: 12),
                if (hasCapacity)
                  _InfoChip(
                    icon: Icons.people,
                    text: spotsLeft > 0
                        ? '$spotsLeft spots left'
                        : 'Full',
                    color: spotsLeft > 0 ? Colors.green : Colors.red,
                  ),
              ],
            ),

          if (timeText.isNotEmpty || hasCapacity)
            const SizedBox(height: 24),

          // Check In button
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onCheckIn?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              'Check In',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Action row: Snooze + Don't Ask Again
          Row(
            children: [
              // Snooze 1 hour
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    GeofenceEngine().snoozeGeofence(_tableId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Snoozed for 1 hour"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: Icon(Icons.snooze, size: 16, color: Colors.grey[500]),
                  label: Text(
                    'Snooze 1h',
                    style: GoogleFonts.inter(
                      color: Colors.grey[500],
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              // Permanent mute
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    GeofenceEngine().muteGeofence(_tableId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("We won't notify you about this again."),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: Icon(Icons.volume_off, size: 16, color: Colors.grey[500]),
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
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
