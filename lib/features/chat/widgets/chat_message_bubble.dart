import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/chat/widgets/poll_message_bubble.dart';

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
  final Function(String userId)? onMentionTap;
  final List<Map<String, dynamic>> participants;
  final String searchQuery;
  final bool isCurrentMatch;

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
    this.onMentionTap,
    this.participants = const [],
    this.searchQuery = '',
    this.isCurrentMatch = false,
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
                                    bottom: hasReactions ? 6.0 : 0,
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
                                        if (msg['contentType'] == 'poll')
                                          PollMessageBubble(
                                            pollId: msg['content'],
                                            isMe: isMe,
                                          )
                                        else if (msg['contentType'] == 'image')
                                          GestureDetector(
                                            onTap: () => _showFullScreenImage(
                                                context, msg['content'] as String),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: CachedNetworkImage(
                                                imageUrl: msg['content'],
                                                width: 220,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Container(
                                                      width: 220,
                                                      height: 160,
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
                                            ),
                                          )
                                        else if (msg['contentType'] == 'gif')
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
                                        else if (msg['deletedAt'] != null &&
                                            (msg['deletedForEveryone'] ||
                                                !isMe))
                                          Text(
                                            '[Message deleted]',
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
                                          )
                                        else
                                          _buildMentionAwareText(
                                            context,
                                            msg['content'] ?? '',
                                            isMe,
                                          ),
                                        if (msg['contentType'] == 'text' ||
                                            msg['contentType'] == null)
                                          Builder(
                                            builder: (context) {
                                              if (msg['content'] == null)
                                                return const SizedBox.shrink();
                                              final urlRegExp = RegExp(
                                                r'https?://[^\s/$.?#].[^\s]*',
                                                caseSensitive: false,
                                              );
                                              final match = urlRegExp
                                                  .firstMatch(msg['content']);
                                              if (match != null) {
                                                final url = msg['content']
                                                    .substring(
                                                      match.start,
                                                      match.end,
                                                    );
                                                
                                                // ✅ Detect image URLs (Supabase storage or common extensions)
                                                final lowerUrl = url.toLowerCase();
                                                final isImageUrl = lowerUrl.contains('/storage/v1/object/') ||
                                                    lowerUrl.endsWith('.jpg') ||
                                                    lowerUrl.endsWith('.jpeg') ||
                                                    lowerUrl.endsWith('.png') ||
                                                    lowerUrl.endsWith('.gif') ||
                                                    lowerUrl.endsWith('.webp') ||
                                                    lowerUrl.contains('.jpg?') ||
                                                    lowerUrl.contains('.jpeg?') ||
                                                    lowerUrl.contains('.png?') ||
                                                    lowerUrl.contains('.webp?');
                                                
                                                if (isImageUrl) {
                                                  // Render as inline image instead of link preview
                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 8.0),
                                                    child: GestureDetector(
                                                      onTap: () => _showFullScreenImage(context, url),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: CachedNetworkImage(
                                                          imageUrl: url,
                                                          width: 220,
                                                          fit: BoxFit.cover,
                                                          placeholder: (context, url) =>
                                                              Container(
                                                                width: 220,
                                                                height: 160,
                                                                color: Colors.grey[200],
                                                                child: const Center(
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth: 2,
                                                                  ),
                                                                ),
                                                              ),
                                                          errorWidget: (context, url, error) =>
                                                              const Icon(Icons.broken_image),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
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
                                                    cache: const Duration(
                                                        days: 7),
                                                    titleStyle: TextStyle(
                                                      color: isMe
                                                          ? Colors.black87
                                                          : Theme.of(
                                                                  context,
                                                                ).brightness ==
                                                                Brightness.dark
                                                          ? Colors.white
                                                          : Colors.black87,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                        LinkableElement(
                                                          url,
                                                          url,
                                                        ),
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

  /// Build text with @mentions highlighted and tappable
  Widget _buildMentionAwareText(
    BuildContext context,
    String text,
    bool isMe,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isMe
        ? Colors.white
        : isDark
            ? Colors.white
            : Colors.black87;
    final mentionColor = isMe ? Colors.amber[200]! : Colors.indigo;
    final linkColor = isMe ? Colors.white : Colors.blue;

    // Pattern: @Name (captures @followed by non-@ chars until space or end)
    final mentionRegex = RegExp(r'@([\w\s]+?)(?=\s@|\s[^@]|$)');
    // URL pattern
    final urlRegex = RegExp(
      r'https?://[^\s/$.?#].[^\s]*',
      caseSensitive: false,
    );

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    // Find all mentions and URLs, sort by position
    final allMatches = <_TextMatch>[];

    for (final match in mentionRegex.allMatches(text)) {
      allMatches.add(_TextMatch(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.mention,
        name: match.group(1)!.trim(),
      ));
    }

    for (final match in urlRegex.allMatches(text)) {
      // Skip if overlaps with a mention
      final overlaps = allMatches.any(
        (m) => m.start <= match.start && m.end >= match.end,
      );
      if (!overlaps) {
        allMatches.add(_TextMatch(
          start: match.start,
          end: match.end,
          text: match.group(0)!,
          type: _MatchType.url,
        ));
      }
    }

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    for (final match in allMatches) {
      // Add plain text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(color: defaultColor, fontSize: 15),
        ));
      }

      if (match.type == _MatchType.mention) {
        // Find userId for this mention
        final userId = _resolveUserId(match.name ?? '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: userId != null && onMentionTap != null
                ? () => onMentionTap!(userId)
                : null,
            child: Text(
              match.text,
              style: TextStyle(
                color: mentionColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ));
      } else {
        // URL
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => onOpenLink(LinkableElement(match.text, match.text)),
            child: Text(
              match.text,
              style: TextStyle(
                color: linkColor,
                fontSize: 15,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
            ),
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(color: defaultColor, fontSize: 15),
      ));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: TextStyle(color: defaultColor, fontSize: 15),
      ));
    }

    // Apply search highlighting if a query is active
    if (searchQuery.isNotEmpty) {
      final highlightedSpans = <InlineSpan>[];
      for (final span in spans) {
        if (span is TextSpan && span.text != null && span.text!.isNotEmpty) {
          highlightedSpans.addAll(
            _highlightSearchMatches(span.text!, span.style ?? TextStyle(color: defaultColor, fontSize: 15)),
          );
        } else {
          highlightedSpans.add(span);
        }
      }
      return RichText(text: TextSpan(children: highlightedSpans));
    }

    return RichText(text: TextSpan(children: spans));
  }

  /// Split text into spans, highlighting substrings that match [searchQuery]
  List<InlineSpan> _highlightSearchMatches(String text, TextStyle baseStyle) {
    final query = searchQuery.toLowerCase();
    final lowerText = text.toLowerCase();
    final result = <InlineSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(query, start);
      if (idx < 0) break;

      // Text before the match
      if (idx > start) {
        result.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }

      // The matched text (use original casing)
      result.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: baseStyle.copyWith(
          backgroundColor: isCurrentMatch
              ? Colors.yellow.withValues(alpha: 0.9)
              : Colors.yellow.withValues(alpha: 0.45),
          color: Colors.black87,
        ),
      ));

      start = idx + query.length;
    }

    // Remaining text after last match
    if (start < text.length) {
      result.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    if (result.isEmpty) {
      result.add(TextSpan(text: text, style: baseStyle));
    }

    return result;
  }

  String? _resolveUserId(String name) {
    final match = participants.where(
      (p) => (p['displayName'] as String?)?.toLowerCase() == name.toLowerCase(),
    );
    return match.isNotEmpty ? match.first['userId'] as String? : null;
  }
}

enum _MatchType { mention, url }

class _TextMatch {
  final int start;
  final int end;
  final String text;
  final _MatchType type;
  final String? name;

  _TextMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
    this.name,
  });
}

/// Shows a full-screen image viewer when a chat image is tapped.
void _showFullScreenImage(BuildContext context, String imageUrl) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    ),
  ));
}
