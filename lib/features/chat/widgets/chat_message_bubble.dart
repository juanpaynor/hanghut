import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

class ChatMessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  final bool showHeader;

  // Computed values passed from parent state
  final String? replySenderName;
  final String? replyContent;
  final Widget statusIndicator;
  final List<Widget> reactionChips;
  final bool hasReactions;

  // Callbacks
  final VoidCallback onReply;
  final VoidCallback onShowActions;
  final VoidCallback onReact; // Double tap quick react
  final Function(LinkableElement) onOpenLink;

  const ChatMessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.showHeader,
    this.replySenderName,
    this.replyContent,
    required this.statusIndicator,
    required this.reactionChips,
    required this.hasReactions,
    required this.onReply,
    required this.onShowActions,
    required this.onReact,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 16 : 4, bottom: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showHeader)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: msg['senderId']),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: msg['senderPhotoUrl'] != null
                      ? NetworkImage(msg['senderPhotoUrl'])
                      : null,
                  child: msg['senderPhotoUrl'] == null
                      ? Icon(Icons.person, size: 16, color: Colors.grey[600])
                      : null,
                ),
              ),
            )
          else if (!isMe)
            const SizedBox(width: 40),

          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showHeader && !isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      msg['senderName'] ?? 'Unknown',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Message Bubble & Actions Wrapper
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Dismissible(
                          key: Key(msg['id'] ?? UniqueKey().toString()),
                          direction: DismissDirection.startToEnd,
                          confirmDismiss: (direction) async {
                            HapticFeedback.mediumImpact();
                            onReply();
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            child: Icon(
                              Icons.reply,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          child: GestureDetector(
                            onLongPress: onShowActions,
                            onDoubleTap: onReact,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: hasReactions ? 12.0 : 0,
                                  ),
                                  child: Container(
                                    padding: msg['contentType'] == 'gif'
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                    decoration: BoxDecoration(
                                      color: msg['contentType'] == 'gif'
                                          ? Colors.transparent
                                          : (isMe
                                                ? Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.blue[700]
                                                      : Colors.black
                                                : Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                ? Colors.grey[800]
                                                : Colors.grey[100]),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(
                                          isMe ? 16 : 4,
                                        ),
                                        bottomRight: Radius.circular(
                                          isMe ? 4 : 16,
                                        ),
                                      ),
                                      // Add shadow to mine for pop
                                      boxShadow:
                                          isMe && msg['contentType'] != 'gif'
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.1,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Reply Preview Inside Bubble
                                        if (msg['reply_to_id'] != null &&
                                            replySenderName != null &&
                                            replyContent != null)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? Colors.white.withValues(
                                                      alpha: 0.2,
                                                    )
                                                  : Colors.black.withValues(
                                                      alpha: 0.05,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border(
                                                left: BorderSide(
                                                  color: isMe
                                                      ? Colors.white
                                                      : Colors.black54,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  replySenderName!,
                                                  style: TextStyle(
                                                    color: isMe
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  replyContent!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: isMe
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.8,
                                                              )
                                                        : Colors.black87
                                                              .withValues(
                                                                alpha: 0.8,
                                                              ),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        // Content
                                        if (msg['contentType'] == 'gif')
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: msg['content'],
                                              width: 200,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  Container(
                                                    width: 200,
                                                    height: 200,
                                                    color: Colors.grey[200],
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(Icons.error),
                                            ),
                                          )
                                        else
                                          Text(
                                            msg['deletedAt'] != null &&
                                                    (msg['deletedForEveryone'] ||
                                                        !isMe)
                                                ? '[Message deleted]'
                                                : '', // Handled below for non-deleted
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : Theme.of(
                                                          context,
                                                        ).brightness ==
                                                        Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 15,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        if (msg['deletedAt'] == null)
                                          Linkify(
                                            onOpen: onOpenLink,
                                            text: msg['content'] ?? '',
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : Theme.of(
                                                          context,
                                                        ).brightness ==
                                                        Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 15,
                                            ),
                                            linkStyle: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : Colors.blue,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor: isMe
                                                  ? Colors.white
                                                  : Colors.blue,
                                            ),
                                          ),
                                        Builder(
                                          builder: (context) {
                                            if (msg['content'] == null)
                                              return const SizedBox.shrink();
                                            final urlRegExp = RegExp(
                                              r'https?://[^\s/$.?#].[^\s]*',
                                              caseSensitive: false,
                                            );
                                            final match = urlRegExp.firstMatch(
                                              msg['content'],
                                            );
                                            if (match != null) {
                                              final url = msg['content']
                                                  .substring(
                                                    match.start,
                                                    match.end,
                                                  );
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8.0,
                                                ),
                                                child: AnyLinkPreview(
                                                  link: url,
                                                  displayDirection: UIDirection
                                                      .uiDirectionVertical,
                                                  showMultimedia: true,
                                                  bodyMaxLines: 3,
                                                  bodyTextOverflow:
                                                      TextOverflow.ellipsis,
                                                  titleStyle: TextStyle(
                                                    color: isMe
                                                        ? Colors.black87
                                                        : Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                  bodyStyle: TextStyle(
                                                    color: isMe
                                                        ? Colors.black54
                                                        : Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                        ? Colors.grey[300]
                                                        : Colors.grey,
                                                    fontSize: 12,
                                                  ),
                                                  backgroundColor: isMe
                                                      ? Colors.white
                                                            .withOpacity(0.9)
                                                      : Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                      ? Colors.grey[800]
                                                      : Colors.grey[200],
                                                  placeholderWidget:
                                                      const SizedBox.shrink(),
                                                  errorWidget:
                                                      const SizedBox.shrink(),
                                                  onTap: () {
                                                    onOpenLink(
                                                      LinkableElement(url, url),
                                                    );
                                                  },
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Positioned Reactions
                                if (hasReactions)
                                  Positioned(
                                    bottom: -8,
                                    left: isMe ? null : 0,
                                    right: isMe ? 0 : null,
                                    child: Wrap(
                                      spacing: 4,
                                      children: reactionChips,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Timestamp & Status (Reactions moved to Stack)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          left: 4,
                          right: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isMe) ...[
                              statusIndicator,
                              const SizedBox(width: 4),
                            ],
                            Text(
                              DateFormat('h:mm a').format(
                                DateTime.parse(msg['timestamp']).toLocal(),
                              ),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
