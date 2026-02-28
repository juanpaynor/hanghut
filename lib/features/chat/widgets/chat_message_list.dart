import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

        // Header Logic: Show if this message is the First (Oldest) of a block.
        final bool showHeader =
            index == messages.length - 1 ||
            messages[index + 1]['senderId'] != msg['senderId'];

        return ChatMessageBubble(
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
        );
      },
    );
  }
}
