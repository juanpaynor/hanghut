import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/core/theme/app_theme.dart';

/// Shown before the mobile event wizard. Recommends the full web builder, but
/// lets the host continue on mobile with the essentials.
///
/// Returns `true` if the host chose to continue creating on mobile; `false`
/// (or null) if they opened the web dashboard or dismissed the sheet.
Future<bool?> showCreateEventRecommendationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _CreateEventRecommendationSheet(),
  );
}

class _CreateEventRecommendationSheet extends StatelessWidget {
  const _CreateEventRecommendationSheet();

  static const _perks = [
    ('mail_outline', 'Custom approval & confirmation emails'),
    ('event_seat_outlined', 'Seat maps & assigned seating'),
    ('brush_outlined', 'Full page design & branding'),
    ('workspace_premium_outlined', 'Subscriber access & early-bird windows'),
  ];

  static const _iconByName = {
    'mail_outline': Icons.mail_outline,
    'event_seat_outlined': Icons.event_seat_outlined,
    'brush_outlined': Icons.brush_outlined,
    'workspace_premium_outlined': Icons.workspace_premium_outlined,
  };

  Future<void> _openWeb(BuildContext context) async {
    final uri = Uri.parse(AppConstants.organizerCreateEventUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.pop(context, false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open the web dashboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.desktop_windows_outlined,
                  color: AppTheme.primaryColor, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              'Create on the web for the full builder',
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              'The web dashboard has everything. On mobile you can set up a solid event with the essentials in a minute — but these live only on the web:',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 18),
            ..._perks.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(_iconByName[p.$1], size: 20, color: Colors.grey[500]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(p.$2,
                            style: GoogleFonts.inter(
                                fontSize: 14, color: Colors.black87)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openWeb(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open web dashboard'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Continue on mobile',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
