import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatParticipantHeader extends StatelessWidget {
  final List<Map<String, dynamic>> participants;
  final Function(String participantId)? onVerifyPressed;
  final VoidCallback? onReadyPressed;

  const ChatParticipantHeader({
    super.key,
    required this.participants,
    this.onVerifyPressed,
    this.onReadyPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Count arrived/verified
    final arrivedCount = participants
        .where((p) => ['arrived', 'verified'].contains(p['arrival_status']))
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : const Color(0xFFF1F5F9),
          ),
        ),
      ),
      child: Row(
        children: [
          // Status Text (Now Interactive)
          GestureDetector(
            onTap: onReadyPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey[800]!.withOpacity(0.6)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$arrivedCount/${participants.length} Ready',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[300] : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: isDark ? Colors.grey[500] : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar list with RSVP-aware rings
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: participants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final p = participants[index];
                  return GestureDetector(
                    onTap: () => onVerifyPressed?.call(p['userId']),
                    child: _buildAvatar(p, isDark),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build avatar with a ring color reflecting RSVP + arrival status.
  /// Priority: arrival_status > rsvp_status > default grey.
  Widget _buildAvatar(Map<String, dynamic> participant, bool isDark) {
    final arrivalStatus = participant['arrival_status'] ?? 'joined';
    final rsvpStatus = participant['rsvp_status'] as String?;

    Color ringColor;
    double ringWidth = 2;

    // Arrival status takes priority (more "real-time" signal)
    switch (arrivalStatus) {
      case 'verified':
        ringColor = const Color(0xFF10B981); // green — verified
        ringWidth = 2.5;
        break;
      case 'arrived':
        ringColor = Colors.orange;
        ringWidth = 2.5;
        break;
      case 'omw':
        ringColor = Colors.yellow.shade700;
        break;
      default:
        // Fall back to RSVP status color
        switch (rsvpStatus) {
          case 'going':
            ringColor = const Color(0xFF10B981); // emerald
            break;
          case 'maybe':
            ringColor = const Color(0xFFF59E0B); // amber
            break;
          case 'not_going':
            ringColor = const Color(0xFFEF4444); // red
            break;
          default:
            ringColor = isDark ? Colors.grey.shade600 : Colors.grey.shade300;
        }
    }

    return Tooltip(
      message: _tooltipText(arrivalStatus, rsvpStatus,
          participant['displayName'] as String? ?? '?'),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: ringWidth),
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[200],
          backgroundImage: participant['photoUrl'] != null
              ? CachedNetworkImageProvider(participant['photoUrl'])
              : null,
          child: participant['photoUrl'] == null
              ? Text(
                  (participant['displayName'] ?? '?')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey[300] : Colors.grey,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String _tooltipText(String arrivalStatus, String? rsvpStatus, String name) {
    switch (arrivalStatus) {
      case 'verified':
        return '$name — Verified ✅';
      case 'arrived':
        return '$name — Arrived 📍';
      case 'omw':
        return '$name — On the way 🚶';
      default:
        break;
    }
    switch (rsvpStatus) {
      case 'going':
        return '$name — Going ✅';
      case 'maybe':
        return '$name — Maybe 🤔';
      case 'not_going':
        return '$name — Can\'t make it ❌';
      default:
        return name;
    }
  }
}
