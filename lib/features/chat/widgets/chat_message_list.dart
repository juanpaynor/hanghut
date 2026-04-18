import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:bitemates/features/chat/widgets/chat_message_bubble.dart';

class ChatMessageList extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final Map<String, List<dynamic>> messageReactions;

  // View builders from parent
  final String Function(String?) getReplySenderName;
  final String Function(String?) getReplyContent;
  final Widget Function(String) buildStatusIndicator;
  final List<Widget> Function(String?) buildReactionChips;

  // Actions
  final Function(Map<String, dynamic>) onReply;
  final Function(Map<String, dynamic>) onShowActions;
  final Function(String, String) onReact;
  final Function(LinkableElement) onOpenLink;
  final Function(String userId)? onMentionTap;
  final Function(String userId)? onAvatarTap;
  final List<Map<String, dynamic>> participants;
  final String searchQuery;
  final List<int> matchedIndices;
  final int currentMatchIndex;

  const ChatMessageList({
    super.key,
    required this.isLoading,
    required this.messages,
    required this.scrollController,
    required this.messageReactions,
    required this.getReplySenderName,
    required this.getReplyContent,
    required this.buildStatusIndicator,
    required this.buildReactionChips,
    required this.onReply,
    required this.onShowActions,
    required this.onReact,
    required this.onOpenLink,
    this.onMentionTap,
    this.onAvatarTap,
    this.participants = const [],
    this.searchQuery = '',
    this.matchedIndices = const [],
    this.currentMatchIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined, // More conversational icon
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text('Say Hi! 👋', style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }

    return ListView.builder(
      reverse: true, // Standard Chat UI: Bottom is start
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMe = msg['isMe'] as bool;

        // Date separator logic (reversed list: index+1 is older)
        bool showDateSeparator = false;
        if (index == messages.length - 1) {
          showDateSeparator = true;
        } else {
          final currentDate = DateTime.parse(msg['timestamp']).toLocal();
          final olderDate = DateTime.parse(
            messages[index + 1]['timestamp'],
          ).toLocal();
          showDateSeparator =
              currentDate.year != olderDate.year ||
              currentDate.month != olderDate.month ||
              currentDate.day != olderDate.day;
        }

        // ── System messages (RSVP changes, check-ins) ──
        if (msg['contentType'] == 'system') {
          final systemChip = _buildSystemMessageChip(
            context,
            msg['content'] ?? '',
          );
          if (showDateSeparator) {
            return Column(
              children: [
                _buildDateChip(
                  context,
                  DateTime.parse(msg['timestamp']).toLocal(),
                ),
                systemChip,
              ],
            );
          }
          return systemChip;
        }

        // Header Logic: Show if this message is the First (Oldest) of a block.
        final bool showHeader =
            index == messages.length - 1 ||
            messages[index + 1]['senderId'] != msg['senderId'] ||
            messages[index + 1]['contentType'] == 'system';

        final bubble = ChatMessageBubble(
          msg: msg,
          isMe: isMe,
          showHeader: showHeader,
          replySenderName: getReplySenderName(msg['reply_to_id']),
          replyContent: getReplyContent(msg['reply_to_id']),
          statusIndicator: buildStatusIndicator(msg['status'] ?? 'sent'),
          reactionChips: buildReactionChips(msg['id']),
          hasReactions: messageReactions[msg['id']]?.isNotEmpty == true,
          onReply: () => onReply(msg),
          onShowActions: () => onShowActions(msg),
          onReact: () {
            HapticFeedback.lightImpact();
            if (msg['id'] != null) {
              onReact(msg['id'], '❤️');
            }
          },
          onOpenLink: onOpenLink,
          onMentionTap: onMentionTap,
          onAvatarTap: onAvatarTap,
          participants: participants,
          searchQuery: searchQuery,
          isCurrentMatch:
              matchedIndices.isNotEmpty &&
              currentMatchIndex >= 0 &&
              currentMatchIndex < matchedIndices.length &&
              matchedIndices[currentMatchIndex] == index,
        );

        if (showDateSeparator) {
          return Column(
            children: [
              _buildDateChip(
                context,
                DateTime.parse(msg['timestamp']).toLocal(),
              ),
              bubble,
            ],
          );
        }

        return bubble;
      },
    );
  }

  /// Renders system messages (RSVP updates, check-ins) as centered, styled pills.
  Widget _buildSystemMessageChip(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey[800]!.withValues(alpha: 0.5)
                : Colors.grey[100]!.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '── $text ──',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final difference = today.difference(messageDay).inDays;

    String label;
    if (difference == 0) {
      label = 'Today';
    } else if (difference == 1) {
      label = 'Yesterday';
    } else if (difference < 7) {
      label = DateFormat('EEEE').format(date); // e.g. "Monday"
    } else if (date.year == now.year) {
      label = DateFormat('EEE, MMM d').format(date); // e.g. "Mon, Mar 30"
    } else {
      label = DateFormat('MMM d, y').format(date); // e.g. "Mar 30, 2025"
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey[800]!.withValues(alpha: 0.8)
                : Colors.grey[200]!.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey[300] : Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
