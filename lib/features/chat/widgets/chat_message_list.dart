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
  final String? Function(String?)? getReplyImageUrl;
  final Widget Function(String) buildStatusIndicator;
  final List<Widget> Function(String?) buildReactionChips;

  // Actions
  final Function(Map<String, dynamic>) onReply;
  final Function(Map<String, dynamic>) onShowActions;
  final Function(String, String) onReact;
  final Function(LinkableElement) onOpenLink;
  final Function(String userId)? onMentionTap;
  final Function(String userId)? onAvatarTap;
  final Function(Map<String, dynamic>)? onRetry;
  final bool Function(String id)? shouldAnimate;
  final List<Map<String, dynamic>> participants;
  final String searchQuery;
  final List<int> matchedIndices;
  final int currentMatchIndex;
  final String channelId;

  const ChatMessageList({
    super.key,
    required this.isLoading,
    required this.messages,
    required this.scrollController,
    required this.messageReactions,
    required this.getReplySenderName,
    required this.getReplyContent,
    this.getReplyImageUrl,
    required this.buildStatusIndicator,
    required this.buildReactionChips,
    required this.onReply,
    required this.onShowActions,
    required this.onReact,
    required this.onOpenLink,
    this.onMentionTap,
    this.onAvatarTap,
    this.onRetry,
    this.shouldAnimate,
    this.participants = const [],
    this.searchQuery = '',
    this.matchedIndices = const [],
    this.currentMatchIndex = -1,
    this.channelId = '',
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

        final String msgId = (msg['id'] ?? '$index').toString();

        // ── System messages (RSVP changes, check-ins) ──
        if (msg['contentType'] == 'system') {
          final systemChip = _buildSystemMessageChip(
            context,
            msg['content'] ?? '',
          );
          if (showDateSeparator) {
            return _wrapAnimated(
              msgId,
              Column(
                children: [
                  _buildDateChip(
                    context,
                    DateTime.parse(msg['timestamp']).toLocal(),
                  ),
                  systemChip,
                ],
              ),
            );
          }
          return _wrapAnimated(msgId, systemChip);
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
          replyImageUrl: getReplyImageUrl?.call(msg['reply_to_id']),
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
          channelId: channelId,
          isCurrentMatch:
              matchedIndices.isNotEmpty &&
              currentMatchIndex >= 0 &&
              currentMatchIndex < matchedIndices.length &&
              matchedIndices[currentMatchIndex] == index,
        );

        // Failed send → show a tappable "retry" caption under the bubble.
        Widget bubbleWidget = bubble;
        if (msg['status'] == 'failed' && onRetry != null) {
          bubbleWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bubble,
              GestureDetector(
                onTap: () => onRetry!(msg),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2, bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: const [
                      Icon(
                        Icons.error_outline,
                        size: 12,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Failed to send. Tap to retry',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (showDateSeparator) {
          return _wrapAnimated(
            msgId,
            Column(
              children: [
                _buildDateChip(
                  context,
                  DateTime.parse(msg['timestamp']).toLocal(),
                ),
                bubbleWidget,
              ],
            ),
          );
        }

        return _wrapAnimated(msgId, bubbleWidget);
      },
    );
  }

  /// Wraps a message row in a one-time fade + slide entrance (only for live
  /// arrivals — history is pre-marked so it renders instantly).
  Widget _wrapAnimated(String id, Widget child) {
    final animate = shouldAnimate?.call(id) ?? false;
    return _AnimatedMessageItem(
      key: ValueKey('anim_$id'),
      animate: animate,
      child: child,
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

/// One-shot fade + slide-up entrance for a newly arrived message. When
/// [animate] is false it renders at rest immediately (used for history so the
/// backlog never animates on open).
class _AnimatedMessageItem extends StatefulWidget {
  final Widget child;
  final bool animate;

  const _AnimatedMessageItem({
    super.key,
    required this.child,
    required this.animate,
  });

  @override
  State<_AnimatedMessageItem> createState() => _AnimatedMessageItemState();
}

class _AnimatedMessageItemState extends State<_AnimatedMessageItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
