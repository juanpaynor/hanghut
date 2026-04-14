import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inline banner in chat showing real-time check-in status.
/// Shows "📍 3/5 checked in" with avatar dots of checked-in members.
class CheckinBanner extends StatefulWidget {
  final String tableId;
  final int totalMembers;
  final List<Map<String, dynamic>> participants;

  const CheckinBanner({
    super.key,
    required this.tableId,
    required this.totalMembers,
    required this.participants,
  });

  @override
  State<CheckinBanner> createState() => _CheckinBannerState();
}

class _CheckinBannerState extends State<CheckinBanner> {
  List<Map<String, dynamic>> _checkins = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadCheckins();
    _subscribeToCheckins();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCheckins() async {
    try {
      final result = await SupabaseConfig.client
          .from('activity_checkins')
          .select('user_id, checkin_type, checked_in_at')
          .eq('table_id', widget.tableId);

      if (mounted) {
        setState(() {
          _checkins = List<Map<String, dynamic>>.from(result);
        });
      }
    } catch (e) {
      print('❌ CheckinBanner: Error loading checkins - $e');
    }
  }

  void _subscribeToCheckins() {
    _channel = SupabaseConfig.client
        .channel('checkin_banner:${widget.tableId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_checkins',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) {
            _loadCheckins();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkins.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checkedInUserIds =
        _checkins.map((c) => c['user_id'] as String).toSet();

    // Get participant photos for checked-in users
    final checkedInParticipants = widget.participants
        .where((p) => checkedInUserIds.contains(p['userId']))
        .toList();

    return GestureDetector(
      onTap: _showCheckinDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0F2A1F)
              : const Color(0xFFF0FDF4),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : const Color(0xFFBBF7D0),
            ),
          ),
        ),
        child: Row(
          children: [
            const Text('📍', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              '${_checkins.length}/${widget.totalMembers} checked in',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 12),
            // Avatar stack
            Expanded(
              child: SizedBox(
                height: 24,
                child: Stack(
                  children: [
                    for (int i = 0;
                        i < checkedInParticipants.length && i < 5;
                        i++)
                      Positioned(
                        left: i * 18.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF0F2A1F)
                                  : const Color(0xFFF0FDF4),
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.grey[300],
                            backgroundImage:
                                checkedInParticipants[i]['photoUrl'] != null
                                    ? CachedNetworkImageProvider(
                                        checkedInParticipants[i]['photoUrl'],
                                      )
                                    : null,
                            child:
                                checkedInParticipants[i]['photoUrl'] == null
                                    ? Text(
                                        (checkedInParticipants[i]
                                                    ['displayName'] ??
                                                '?')
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : null,
                          ),
                        ),
                      ),
                    if (checkedInParticipants.length > 5)
                      Positioned(
                        left: 5 * 18.0,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: isDark
                              ? Colors.grey[700]
                              : Colors.grey[300],
                          child: Text(
                            '+${checkedInParticipants.length - 5}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckinDetails() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checkedInUserIds =
        _checkins.map((c) => c['user_id'] as String).toSet();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 16),
            Text(
              'Check-in Status',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...widget.participants.map((p) {
              final isCheckedIn =
                  checkedInUserIds.contains(p['userId']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: p['photoUrl'] != null
                          ? CachedNetworkImageProvider(p['photoUrl'])
                          : null,
                      child: p['photoUrl'] == null
                          ? Text(
                              (p['displayName'] ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p['displayName'] ?? 'Unknown',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCheckedIn
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isCheckedIn ? '✅ Checked in' : '⏳ Waiting',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isCheckedIn ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
