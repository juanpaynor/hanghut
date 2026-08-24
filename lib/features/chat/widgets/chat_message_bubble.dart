import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/chat/widgets/poll_message_bubble.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';
import 'package:bitemates/features/sharing/widgets/share_card.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/home/screens/post_detail_screen.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/map/widgets/liquid_morph_route.dart';
import 'package:bitemates/core/services/experience_service.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';

class ChatMessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  final bool showHeader;

  // Computed values passed from parent state
  final String? replySenderName;
  final String? replyContent;
  // Thumbnail URL when the replied-to message is an image/gif (shows a preview
  // in the quoted reply instead of just a generic icon).
  final String? replyImageUrl;
  final Widget statusIndicator;
  final List<Widget> reactionChips;
  final bool hasReactions;

  // Callbacks
  final VoidCallback onReply;
  final VoidCallback onShowActions;
  final VoidCallback onReact; // Double tap quick react
  final Function(LinkableElement) onOpenLink;
  final Function(String userId)? onMentionTap;
  final Function(String userId)? onAvatarTap;
  final List<Map<String, dynamic>> participants;
  final String searchQuery;
  final String channelId;
  final bool isCurrentMatch;

  const ChatMessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.showHeader,
    this.replySenderName,
    this.replyContent,
    this.replyImageUrl,
    required this.statusIndicator,
    required this.reactionChips,
    required this.hasReactions,
    required this.onReply,
    required this.onShowActions,
    required this.onReact,
    required this.onOpenLink,
    this.onMentionTap,
    this.onAvatarTap,
    this.participants = const [],
    this.searchQuery = '',
    this.channelId = '',
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
                  if (onAvatarTap != null) {
                    onAvatarTap!(msg['senderId']);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UserProfileScreen(userId: msg['senderId']),
                      ),
                    );
                  }
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

                // Message Bubble & Actions Wrapper.
                // Entrance animation is handled once, higher up, by
                // _AnimatedMessageItem (only for live arrivals). Keeping a second
                // fade/translate here caused a visible "double bounce" and also
                // re-animated every bubble on scroll recycle — so it's disabled
                // (begin == end == 1 → renders at rest).
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: 1),
                  duration: Duration.zero,
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
                                    padding:
                                        (msg['contentType'] == 'gif' ||
                                            msg['contentType'] == 'share')
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                    decoration: BoxDecoration(
                                      // Your bubbles carry the brand accent in
                                      // both themes (text is already white);
                                      // others stay neutral light/dark grey.
                                      color:
                                          (msg['contentType'] == 'gif' ||
                                              msg['contentType'] == 'share')
                                          ? Colors.transparent
                                          : (isMe
                                                ? Theme.of(context).primaryColor
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
                                        // Forwarded tag
                                        if (msg['isForwarded'] == true)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.forward,
                                                  size: 12,
                                                  color: (isMe &&
                                                          msg['contentType'] !=
                                                              'gif' &&
                                                          msg['contentType'] !=
                                                              'share')
                                                      ? Colors.white70
                                                      : Colors.grey[600],
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Forwarded',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                    color: (isMe &&
                                                            msg['contentType'] !=
                                                                'gif' &&
                                                            msg['contentType'] !=
                                                                'share')
                                                        ? Colors.white70
                                                        : Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                if (replyImageUrl != null) ...[
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                    child: CachedNetworkImage(
                                                      imageUrl: replyImageUrl!,
                                                      width: 32,
                                                      height: 32,
                                                      fit: BoxFit.cover,
                                                      placeholder: (_, __) =>
                                                          Container(
                                                            width: 32,
                                                            height: 32,
                                                            color: Colors.black
                                                                .withValues(
                                                                  alpha: 0.08,
                                                                ),
                                                          ),
                                                      errorWidget:
                                                          (_, __, ___) => Icon(
                                                            Icons.image,
                                                            size: 18,
                                                            color: isMe
                                                                ? Colors.white70
                                                                : Colors.black45,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                Flexible(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      Text(
                                                        replyContent!,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                              ],
                                            ),
                                          ),

                                        // Content
                                        if (msg['deletedAt'] != null &&
                                            (msg['deletedForEveryone'] ==
                                                    true ||
                                                !isMe))
                                          Text(
                                            '🚫 Message deleted',
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white70
                                                  : (Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.white54
                                                        : Colors.black45),
                                              fontSize: 14,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        else if (msg['contentType'] == 'poll')
                                          PollMessageBubble(
                                            pollId: msg['content'],
                                            isMe: isMe,
                                            channelId: channelId,
                                          )
                                        else if (msg['contentType'] == 'image')
                                          GestureDetector(
                                            onTap: () => _showFullScreenImage(
                                              context,
                                              msg['content'] as String,
                                            ),
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
                                        else if (msg['contentType'] == 'share')
                                          _buildShareCard(
                                            context,
                                            msg['content'] ?? '',
                                            isMe,
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
                                                final lowerUrl = url
                                                    .toLowerCase();
                                                final isImageUrl =
                                                    lowerUrl.contains(
                                                      '/storage/v1/object/',
                                                    ) ||
                                                    lowerUrl.endsWith('.jpg') ||
                                                    lowerUrl.endsWith(
                                                      '.jpeg',
                                                    ) ||
                                                    lowerUrl.endsWith('.png') ||
                                                    lowerUrl.endsWith('.gif') ||
                                                    lowerUrl.endsWith(
                                                      '.webp',
                                                    ) ||
                                                    lowerUrl.contains(
                                                      '.jpg?',
                                                    ) ||
                                                    lowerUrl.contains(
                                                      '.jpeg?',
                                                    ) ||
                                                    lowerUrl.contains(
                                                      '.png?',
                                                    ) ||
                                                    lowerUrl.contains('.webp?');

                                                if (isImageUrl) {
                                                  // Render as inline image instead of link preview
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 8.0,
                                                        ),
                                                    child: GestureDetector(
                                                      onTap: () =>
                                                          _showFullScreenImage(
                                                            context,
                                                            url,
                                                          ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        child: CachedNetworkImage(
                                                          imageUrl: url,
                                                          width: 220,
                                                          fit: BoxFit.cover,
                                                          placeholder:
                                                              (
                                                                context,
                                                                url,
                                                              ) => Container(
                                                                width: 220,
                                                                height: 160,
                                                                color: Colors
                                                                    .grey[200],
                                                                child: const Center(
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                ),
                                                              ),
                                                          errorWidget:
                                                              (
                                                                context,
                                                                url,
                                                                error,
                                                              ) => const Icon(
                                                                Icons
                                                                    .broken_image,
                                                              ),
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
                                                      days: 7,
                                                    ),
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
                                                        _linkLoadingCard(
                                                          context,
                                                          isMe,
                                                        ),
                                                    errorWidget: _linkErrorCard(
                                                      context,
                                                      url,
                                                      isMe,
                                                    ),
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
  /// Shown while a link's metadata is being fetched.
  Widget _linkLoadingCard(BuildContext context, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      height: 56,
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.85)
            : (isDark ? Colors.grey[800] : Colors.grey[200]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// Fallback when a site returns no preview metadata: a tappable card with the
  /// host + URL so a link never renders as "nothing".
  Widget _linkErrorCard(BuildContext context, String url, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final host = Uri.tryParse(url)?.host ?? url;
    final fg = isMe ? Colors.black87 : (isDark ? Colors.white : Colors.black87);
    final sub = isMe
        ? Colors.black54
        : (isDark ? Colors.grey[400] : Colors.grey[600]);
    return GestureDetector(
      onTap: () => onOpenLink(LinkableElement(url, url)),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.85)
              : (isDark ? Colors.grey[800] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.link, size: 18, color: sub),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sub, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders a shared entity (event/hangout/…) as a ShareCard bubble. Falls
  /// back to the raw text if the content isn't a valid share envelope.
  Widget _buildShareCard(BuildContext context, String content, bool isMe) {
    final payload = SharePayload.tryParseMessageContent(content);
    if (payload == null) {
      return _buildMentionAwareText(context, content, isMe);
    }
    final card = _buildShareCardBody(context, payload, isMe);
    final note = payload.note;
    if (note == null || note.isEmpty) return card;
    // The share bubble itself is transparent, so the caption gets its own mini
    // bubble (matching the normal text-bubble colors) sitting above the card,
    // reading as "your note + the card" — one message.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe
                ? Theme.of(context).primaryColor
                : (isDark ? Colors.grey[800] : Colors.grey[100]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            note,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: isMe
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ),
        card,
      ],
    );
  }

  Widget _buildShareCardBody(
    BuildContext context,
    SharePayload payload,
    bool isMe,
  ) {
    return ShareCard(
      payload: payload,
      onTap: () => _openSharedEntity(context, payload),
      action: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _openSharedEntity(context, payload),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            payload.type == ShareEntityType.event
                ? 'View event'
                : payload.type == ShareEntityType.post
                ? 'View post'
                : payload.type == ShareEntityType.hangout
                ? 'View hangout'
                : payload.type == ShareEntityType.experience
                ? 'View experience'
                : 'View',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  /// Opens the shared entity. Only events are routable today (Phase 1); other
  /// types are parked until their open-by-id surfaces exist.
  Future<void> _openSharedEntity(
    BuildContext context,
    SharePayload payload,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Posts open by id directly — no fetch needed.
    if (payload.type == ShareEntityType.post) {
      navigator.push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: payload.id)),
      );
      return;
    }

    // Events: fetch then open the detail modal.
    if (payload.type == ShareEntityType.event) {
      try {
        final event = await EventService().getEvent(payload.id);
        if (event == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('This event is no longer available.')),
          );
          return;
        }
        navigator.push(
          MaterialPageRoute(builder: (_) => EventDetailModal(event: event)),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that event.")),
        );
      }
      return;
    }

    // Hangouts: fetch the tables row by id, then open the same compact modal
    // the map uses (via LiquidMorphRoute).
    if (payload.type == ShareEntityType.hangout) {
      final size = MediaQuery.of(context).size;
      try {
        final table = await SupabaseConfig.client
            .from('tables')
            .select('*')
            .eq('id', payload.id)
            .maybeSingle();
        if (table == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('This hangout is no longer available.'),
            ),
          );
          return;
        }
        navigator.push(
          LiquidMorphRoute(
            center: Offset(size.width / 2, size.height / 2),
            page: TableCompactModal(table: Map<String, dynamic>.from(table)),
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that hangout.")),
        );
      }
      return;
    }

    // Experiences (also `tables` rows): fetch via ExperienceService and open the
    // experience detail modal.
    if (payload.type == ShareEntityType.experience) {
      try {
        final experience =
            await ExperienceService().getExperienceDetails(payload.id);
        if (experience.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('This experience is no longer available.'),
            ),
          );
          return;
        }
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ExperienceDetailModal(
              experience: experience,
              matchData: const {},
            ),
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that experience.")),
        );
      }
      return;
    }
  }

  Widget _buildMentionAwareText(BuildContext context, String text, bool isMe) {
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
      allMatches.add(
        _TextMatch(
          start: match.start,
          end: match.end,
          text: match.group(0)!,
          type: _MatchType.mention,
          name: match.group(1)!.trim(),
        ),
      );
    }

    for (final match in urlRegex.allMatches(text)) {
      // Skip if overlaps with a mention
      final overlaps = allMatches.any(
        (m) => m.start <= match.start && m.end >= match.end,
      );
      if (!overlaps) {
        allMatches.add(
          _TextMatch(
            start: match.start,
            end: match.end,
            text: match.group(0)!,
            type: _MatchType.url,
          ),
        );
      }
    }

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    for (final match in allMatches) {
      // Add plain text before this match
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(color: defaultColor, fontSize: 15),
          ),
        );
      }

      if (match.type == _MatchType.mention) {
        // Find userId for this mention
        final userId = _resolveUserId(match.name ?? '');
        spans.add(
          WidgetSpan(
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
          ),
        );
      } else {
        // URL
        spans.add(
          WidgetSpan(
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
          ),
        );
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(color: defaultColor, fontSize: 15),
        ),
      );
    }

    if (spans.isEmpty) {
      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(color: defaultColor, fontSize: 15),
        ),
      );
    }

    // Apply search highlighting if a query is active
    if (searchQuery.isNotEmpty) {
      final highlightedSpans = <InlineSpan>[];
      for (final span in spans) {
        if (span is TextSpan && span.text != null && span.text!.isNotEmpty) {
          highlightedSpans.addAll(
            _highlightSearchMatches(
              span.text!,
              span.style ?? TextStyle(color: defaultColor, fontSize: 15),
            ),
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
        result.add(
          TextSpan(text: text.substring(start, idx), style: baseStyle),
        );
      }

      // The matched text (use original casing)
      result.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: baseStyle.copyWith(
            backgroundColor: isCurrentMatch
                ? Colors.yellow.withValues(alpha: 0.9)
                : Colors.yellow.withValues(alpha: 0.45),
            color: Colors.black87,
          ),
        ),
      );

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
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _FullScreenImagePage(imageUrl: imageUrl),
    ),
  );
}

class _FullScreenImagePage extends StatefulWidget {
  final String imageUrl;
  const _FullScreenImagePage({required this.imageUrl});

  @override
  State<_FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<_FullScreenImagePage> {
  bool _downloading = false;

  Future<void> _downloadImage() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // Write to a temp file, then hand off to the OS share sheet — where
      // "Save Image" / "Save to Photos" is a one-tap option. This avoids a
      // native gallery-saver plugin, keeping the feature Shorebird-patchable.
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/hanghut_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(response.bodyBytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } catch (e) {
      debugPrint('❌ Download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download image')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_downloading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Save to gallery',
              onPressed: _downloadImage,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
