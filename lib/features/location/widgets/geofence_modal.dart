import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';

class GeofenceModal extends StatelessWidget {
  final String tableId;
  final String tableName;
  final VoidCallback? onCheckIn;

  const GeofenceModal({
    super.key,
    required this.tableId,
    required this.tableName,
    this.onCheckIn,
  });

  static Future<void> show(
    BuildContext context, {
    required String tableId,
    required String tableName,
    VoidCallback? onCheckIn,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GeofenceModal(
        tableId: tableId,
        tableName: tableName,
        onCheckIn: onCheckIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
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
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.place_rounded,
                size: 32,
                color: AppTheme.accentColor,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Text
          Text(
            "You're near $tableName!",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Would you like to check in and see who's here?",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Buttons
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onCheckIn?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Check In'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              // Mute logic
              GeofenceEngine().muteGeofence(tableId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("We won't notify you about this table again."),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text("Don't ask me again"),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
