import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatParticipantHeader extends StatelessWidget {
  final List<Map<String, dynamic>> participants;
  final Function(String participantId)? onVerifyPressed;
  final VoidCallback? onReadyPressed; // New callback

  const ChatParticipantHeader({
    super.key,
    required this.participants,
    this.onVerifyPressed,
    this.onReadyPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();

    // Count arrived/verified
    final arrivedCount = participants
        .where((p) => ['arrived', 'verified'].contains(p['arrival_status']))
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // Status Text (Now Interactive)
          GestureDetector(
            onTap: onReadyPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$arrivedCount/${participants.length} Ready',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: Colors.grey,
                  ), // Hint arrow
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ... rest of the build method
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
                    child: _buildAvatar(p),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Map<String, dynamic> participant) {
    final status = participant['arrival_status'] ?? 'joined';
    Color ringColor;

    switch (status) {
      case 'verified':
        ringColor = Colors.green;
        break;
      case 'arrived':
        ringColor = Colors.orange;
        break;
      case 'omw':
        ringColor = Colors.yellow.shade700;
        break;
      default:
        ringColor = Colors.grey.shade300;
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      padding: const EdgeInsets.all(2), // Space between ring and image
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[200],
        backgroundImage: participant['photoUrl'] != null
            ? CachedNetworkImageProvider(participant['photoUrl'])
            : null,
        child: participant['photoUrl'] == null
            ? Text(
                (participant['displayName'] ?? '?')
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              )
            : null,
      ),
    );
  }
}
