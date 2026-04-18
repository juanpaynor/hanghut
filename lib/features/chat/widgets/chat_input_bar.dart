import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final Map<String, dynamic>? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onShowGifPicker;
  final VoidCallback onSendMessage;
  final VoidCallback? onSendImage; // null = image not supported
  final VoidCallback? onCreatePoll; // null = polls not supported (DMs)
  final List<Map<String, dynamic>> participants;

  const ChatInputBar({
    super.key,
    required this.controller,
    this.replyingTo,
    required this.onCancelReply,
    required this.onShowGifPicker,
    required this.onSendMessage,
    this.onSendImage,
    this.onCreatePoll,
    this.participants = const [],
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _showMentionOverlay = false;
  String _mentionQuery = '';
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    if (cursorPos <= 0 || cursorPos > text.length) {
      if (_showMentionOverlay) setState(() => _showMentionOverlay = false);
      return;
    }

    final beforeCursor = text.substring(0, cursorPos);
    final lastAtIndex = beforeCursor.lastIndexOf('@');

    if (lastAtIndex == -1) {
      if (_showMentionOverlay) setState(() => _showMentionOverlay = false);
      return;
    }

    final textAfterAt = beforeCursor.substring(lastAtIndex + 1);
    if (textAfterAt.contains(' ') || textAfterAt.contains('\n')) {
      if (_showMentionOverlay) setState(() => _showMentionOverlay = false);
      return;
    }

    if (lastAtIndex > 0 && text[lastAtIndex - 1] != ' ') {
      if (_showMentionOverlay) setState(() => _showMentionOverlay = false);
      return;
    }

    setState(() {
      _showMentionOverlay = true;
      _mentionStartIndex = lastAtIndex;
      _mentionQuery = textAfterAt.toLowerCase();
    });
  }

  void _selectMention(Map<String, dynamic> participant) {
    final text = widget.controller.text;
    final displayName = participant['displayName'] as String;
    final before = text.substring(0, _mentionStartIndex);
    final cursorPos = widget.controller.selection.baseOffset;
    final after = cursorPos < text.length ? text.substring(cursorPos) : '';
    final newText = '$before@$displayName $after';
    widget.controller.text = newText;
    widget.controller.selection = TextSelection.collapsed(
      offset: _mentionStartIndex + displayName.length + 2,
    );
    setState(() {
      _showMentionOverlay = false;
      _mentionQuery = '';
      _mentionStartIndex = -1;
    });
  }

  List<Map<String, dynamic>> get _filteredParticipants {
    if (_mentionQuery.isEmpty) return widget.participants;
    return widget.participants.where((p) {
      final name = (p['displayName'] as String?)?.toLowerCase() ?? '';
      return name.contains(_mentionQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mentions overlay
        if (_showMentionOverlay && _filteredParticipants.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filteredParticipants.length,
                itemBuilder: (context, index) {
                  final p = _filteredParticipants[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: p['photoUrl'] != null
                          ? NetworkImage(p['photoUrl'])
                          : null,
                      child: p['photoUrl'] == null
                          ? Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey[600],
                            )
                          : null,
                    ),
                    title: Text(
                      p['displayName'] ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    onTap: () => _selectMention(p),
                  );
                },
              ),
            ),
          ),

        // Input area
        Container(
          padding: const EdgeInsets.only(
            left: 8,
            right: 16,
            top: 12,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Reply preview
                if (widget.replyingTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.blue[400] : Colors.black,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Replying to ${widget.replyingTo!['senderName'] ?? 'Unknown'}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final raw =
                                      (widget.replyingTo!['content'] ?? '')
                                          .toString();
                                  final isImage =
                                      raw.contains('.jpg') ||
                                      raw.contains('.jpeg') ||
                                      raw.contains('.png') ||
                                      raw.contains('.webp') ||
                                      raw.contains('.gif') ||
                                      raw.contains('supabase') ||
                                      raw.contains('storage/v1/object');
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isImage) ...[
                                        Icon(
                                          Icons.image_rounded,
                                          size: 14,
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(0.7),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Flexible(
                                        child: Text(
                                          isImage ? 'Image' : raw,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.black54,
                          ),
                          onPressed: widget.onCancelReply,
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    // GIF button
                    IconButton(
                      icon: Icon(
                        Icons.gif_box_outlined,
                        color: isDark ? Colors.grey[400] : Colors.black54,
                      ),
                      onPressed: widget.onShowGifPicker,
                      tooltip: 'GIF',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    // Image button
                    if (widget.onSendImage != null)
                      IconButton(
                        icon: Icon(
                          Icons.image_outlined,
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        onPressed: widget.onSendImage,
                        tooltip: 'Photo',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    // Poll button (group chats only)
                    if (widget.onCreatePoll != null)
                      IconButton(
                        icon: Icon(
                          Icons.poll_outlined,
                          color: isDark ? Colors.grey[400] : Colors.black54,
                        ),
                        onPressed: widget.onCreatePoll,
                        tooltip: 'Poll',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 4),
                    // Text Input
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: widget.controller,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Send button
                    GestureDetector(
                      onTap: widget.onSendMessage,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
