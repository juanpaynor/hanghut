import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/home/widgets/mention_overlay.dart';
import 'package:bitemates/features/home/widgets/mention_text.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';

class CommentsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> post;

  const CommentsBottomSheet({super.key, required this.post});

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 50;

  // Reply state
  String? _replyingToId;
  String? _replyingToName;

  // Media attachment state
  File? _selectedImage;
  String? _selectedGifUrl;

  // Mention state
  bool _showMentionOverlay = false;
  String? _mentionQuery;

  // Expand/collapse state for reply threads
  final Set<String> _expandedThreads = {};

  // Available emoji reactions
  static const List<String> _reactionEmojis = [
    '❤️',
    '😂',
    '😮',
    '😢',
    '🔥',
    '👏',
  ];

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollController.addListener(_onScroll);
    _commentController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _commentController.removeListener(_onTextChanged);
    _commentController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreComments();
      }
    }
  }

  // --- Data: Build thread tree ---

  /// Group comments into parent → children map.
  /// Returns top-level parents in chronological order.
  List<Map<String, dynamic>> get _parentComments {
    return _comments.where((c) => c['parent_id'] == null).toList();
  }

  /// Get replies for a given parent comment.
  List<Map<String, dynamic>> _getReplies(String parentId) {
    return _comments.where((c) => c['parent_id'] == parentId).toList();
  }

  // --- Data: Load & Post ---

  Future<void> _loadComments() async {
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final result = await SocialService().getComments(postId, limit: _pageSize, offset: 0);
      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(result['comments'] ?? []);
          _hasMore = result['hasMore'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading comments: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasMore) return;
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) return;

    setState(() => _isLoadingMore = true);
    try {
      final result = await SocialService().getComments(
        postId,
        limit: _pageSize,
        offset: _comments.length,
      );
      if (mounted) {
        setState(() {
          final newComments = List<Map<String, dynamic>>.from(result['comments'] ?? []);
          _comments.addAll(newComments);
          _hasMore = result['hasMore'] ?? false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Error loading more comments: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _selectedImage == null && _selectedGifUrl == null) return;

    setState(() => _isPosting = true);

    try {
      final postId = widget.post['id']?.toString();
      if (postId == null || postId.isEmpty) return;

      // Resolve @mentions to UUIDs
      List<String>? mentionedUserIds;
      final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
      final usernames = mentionRegex.allMatches(text).map((m) => m.group(1)!).toSet().toList();
      if (usernames.isNotEmpty) {
        final usernameToId = await SocialService().resolveUsernames(usernames);
        mentionedUserIds = usernameToId.values.toList();
      }

      final comment = await SocialService().addComment(
        postId: postId,
        content: text,
        parentId: _replyingToId,
        imageFile: _selectedImage,
        gifUrl: _selectedGifUrl,
        mentionedUserIds: mentionedUserIds,
      );

      if (comment != null && mounted) {
        _commentController.clear();
        _clearReplyState();
        _clearMedia();
        // If posting a reply, auto-expand that thread
        if (comment['parent_id'] != null) {
          _expandedThreads.add(comment['parent_id']);
        }
        _loadComments(); // Refresh to get full data with joins
      }
    } catch (e) {
      print('Error posting comment: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // --- Mention Detection ---

  void _onTextChanged() {
    final text = _commentController.text;
    final cursorPos = _commentController.selection.baseOffset;
    if (cursorPos < 0 || cursorPos > text.length) {
      _hideMentionOverlay();
      return;
    }

    final beforeCursor = text.substring(0, cursorPos);
    final mentionMatch = RegExp(r'@([a-zA-Z0-9_]*)$').firstMatch(beforeCursor);

    if (mentionMatch != null) {
      final query = mentionMatch.group(1) ?? '';
      setState(() {
        _showMentionOverlay = true;
        _mentionQuery = query;
      });
    } else {
      _hideMentionOverlay();
    }
  }

  void _hideMentionOverlay() {
    if (_showMentionOverlay) {
      setState(() {
        _showMentionOverlay = false;
        _mentionQuery = null;
      });
    }
  }

  void _onMentionSelected(Map<String, dynamic> user) {
    final username = user['username'] as String? ?? '';
    if (username.isEmpty) return;

    final text = _commentController.text;
    final cursorPos = _commentController.selection.baseOffset;
    final beforeCursor = text.substring(0, cursorPos);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0) return;

    final afterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}@$username $afterCursor';
    _commentController.text = newText;
    final newCursorPos = atIndex + username.length + 2;
    _commentController.selection = TextSelection.collapsed(offset: newCursorPos);
    _hideMentionOverlay();
  }

  // --- Media Pickers ---

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedGifUrl = null; // Mutually exclusive
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _pickGif() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TenorGifPicker(
        onGifSelected: (gifUrl) {
          setState(() {
            _selectedGifUrl = gifUrl;
            _selectedImage = null; // Mutually exclusive
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _clearMedia() {
    setState(() {
      _selectedImage = null;
      _selectedGifUrl = null;
    });
  }

  Future<void> _toggleLike(String commentId) async {
    // Optimistic update
    final index = _comments.indexWhere((c) => c['id'] == commentId);
    if (index != -1) {
      final comment = _comments[index];
      final wasLiked = comment['is_liked'] ?? false;
      setState(() {
        _comments[index] = {
          ...comment,
          'is_liked': !wasLiked,
          'like_count': (comment['like_count'] ?? 0) + (wasLiked ? -1 : 1),
        };
      });
    }
    await SocialService().toggleCommentLike(commentId);
  }

  Future<void> _toggleReaction(String commentId, String emoji) async {
    // Optimistic update
    final index = _comments.indexWhere((c) => c['id'] == commentId);
    if (index != -1) {
      final comment = Map<String, dynamic>.from(_comments[index]);
      final reactions = Map<String, Map<String, dynamic>>.from(
        (comment['reactions'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
            ) ??
            {},
      );

      if (reactions.containsKey(emoji) &&
          reactions[emoji]!['is_reacted'] == true) {
        // Remove reaction
        reactions[emoji]!['count'] = (reactions[emoji]!['count'] as int) - 1;
        reactions[emoji]!['is_reacted'] = false;
        if (reactions[emoji]!['count'] <= 0) {
          reactions.remove(emoji);
        }
      } else {
        // Add reaction
        if (reactions.containsKey(emoji)) {
          reactions[emoji]!['count'] = (reactions[emoji]!['count'] as int) + 1;
          reactions[emoji]!['is_reacted'] = true;
        } else {
          reactions[emoji] = {'count': 1, 'is_reacted': true};
        }
      }

      setState(() {
        comment['reactions'] = reactions;
        _comments[index] = comment;
      });
    }

    await SocialService().toggleCommentReaction(commentId, emoji);
  }

  void _startReply(String commentId, String userName) {
    setState(() {
      // If the comment being replied to is itself a reply, reply to the parent instead
      final comment = _comments.firstWhere(
        (c) => c['id'] == commentId,
        orElse: () => {},
      );
      _replyingToId = comment['parent_id'] ?? commentId;
      _replyingToName = userName;
    });
    _inputFocusNode.requestFocus();
  }

  void _clearReplyState() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  void _showEmojiPicker(String commentId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'React',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _reactionEmojis.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _toggleReaction(commentId, emoji);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _parentComments.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _parentComments.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final parent = _parentComments[index];
                      return _buildCommentThread(parent);
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final commentCount = _comments.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              commentCount > 0 ? 'Comments ($commentCount)' : 'Comments',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.grey[600]),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No comments yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to comment!',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // --- Comment Thread (Parent + Replies) ---

  Widget _buildCommentThread(Map<String, dynamic> parent) {
    final replies = _getReplies(parent['id']);
    final isExpanded = _expandedThreads.contains(parent['id']);
    final hasReplies = replies.isNotEmpty;
    final showExpandButton = replies.length > 2 && !isExpanded;
    final displayedReplies = isExpanded ? replies : replies.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Parent comment
        _buildCommentCard(parent, isReply: false),

        // Replies
        if (hasReplies)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey[300]!, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...displayedReplies.map(
                    (reply) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _buildCommentCard(reply, isReply: true),
                    ),
                  ),

                  // "View N more replies" expand button
                  if (showExpandButton)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedThreads.add(parent['id']);
                          });
                        },
                        child: Text(
                          '── View ${replies.length - 2} more ${replies.length - 2 == 1 ? 'reply' : 'replies'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),

                  // Collapse button
                  if (isExpanded && replies.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedThreads.remove(parent['id']);
                          });
                        },
                        child: Text(
                          '── Hide replies',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- Single Comment Card ---

  Widget _buildCommentCard(
    Map<String, dynamic> comment, {
    required bool isReply,
  }) {
    final timestamp = DateTime.tryParse(comment['created_at'] ?? '');
    final timeAgo = timestamp != null ? timeago.format(timestamp) : '';
    final user = comment['user'] as Map<String, dynamic>?;
    final userName = user?['display_name'] ?? 'User';
    final userAvatar = user?['avatar_url'] as String?;
    final isLiked = comment['is_liked'] ?? false;
    final likeCount = comment['like_count'] ?? 0;
    final reactions =
        (comment['reactions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        ) ??
        {};
    final isOwner =
        comment['user_id'] == SupabaseConfig.client.auth.currentUser?.id;

    return GestureDetector(
      onLongPress: () => _showEmojiPicker(comment['id']),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            GestureDetector(
              onTap: () {
                final userId = comment['user_id'] as String?;
                if (userId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(userId: userId),
                    ),
                  );
                }
              },
              child: CircleAvatar(
                radius: isReply ? 14 : 18,
                backgroundColor: Colors.grey[300],
                backgroundImage: userAvatar != null
                    ? NetworkImage(userAvatar)
                    : null,
                child: userAvatar == null
                    ? Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: isReply ? 11 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Comment bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MentionText(
                          text: comment['content'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
                          ),
                        ),
                        // Attached image
                        if (comment['image_url'] != null && (comment['image_url'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenImageViewer(
                                    imageUrl: comment['image_url'],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: comment['image_url'],
                                maxHeightDiskCache: 400,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 120,
                                  color: Colors.grey[200],
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 60,
                                  color: Colors.grey[100],
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ],
                        // Attached GIF
                        if (comment['gif_url'] != null && (comment['gif_url'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              comment['gif_url'],
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 100,
                                  color: Colors.grey[200],
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 60,
                                  color: Colors.grey[100],
                                  child: const Icon(Icons.gif_box_outlined, color: Colors.grey),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Emoji reaction bubbles
                  if (reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: reactions.entries.map((entry) {
                          final emoji = entry.key;
                          final count = entry.value['count'] as int;
                          final isReacted = entry.value['is_reacted'] as bool;
                          return GestureDetector(
                            onTap: () => _toggleReaction(comment['id'], emoji),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isReacted
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isReacted
                                      ? Colors.blue.withValues(alpha: 0.4)
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  if (count > 1) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isReacted
                                            ? Colors.blue
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // Actions row
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 16),

                      // Like
                      GestureDetector(
                        onTap: () => _toggleLike(comment['id']),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: isLiked ? Colors.red : Colors.grey[600],
                            ),
                            if (likeCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '$likeCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLiked
                                      ? Colors.red
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Reply
                      GestureDetector(
                        onTap: () => _startReply(comment['id'], userName),
                        child: Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),

                      // React (emoji button)
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _showEmojiPicker(comment['id']),
                        child: Icon(
                          Icons.add_reaction_outlined,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                      ),

                      // Delete (only for owner)
                      if (isOwner) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _deleteComment(comment['id']),
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await SocialService().deleteComment(commentId);
      if (success && mounted) {
        setState(() {
          _comments.removeWhere((c) => c['id'] == commentId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Comment deleted')));
      }
    }
  }

  // --- Input Area with Reply Banner ---

  String? _currentUserAvatarUrl;

  Widget _buildInputArea() {
    // Fetch current user avatar from user_photos if not cached
    if (_currentUserAvatarUrl == null) {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        SupabaseConfig.client
            .from('user_photos')
            .select('photo_url')
            .eq('user_id', userId)
            .eq('is_primary', true)
            .limit(1)
            .then((res) {
          if (res.isNotEmpty && mounted) {
            setState(() {
              _currentUserAvatarUrl = res[0]['photo_url'] as String?;
            });
          }
        }).catchError((_) {});
      }
    }
    final avatarUrl = _currentUserAvatarUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMedia = _selectedImage != null || _selectedGifUrl != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mention overlay (positioned above input)
        if (_showMentionOverlay && _mentionQuery != null)
          MentionOverlay(
            query: _mentionQuery!,
            onUserSelected: _onMentionSelected,
          ),

        // Reply-to banner
        if (_replyingToId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? Colors.grey[850] : Colors.grey[100],
            child: Row(
              children: [
                Icon(Icons.reply, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Replying to ',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                Text(
                  _replyingToName ?? 'User',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearReplyState,
                  child: Icon(Icons.close, size: 18, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

        // Media preview strip
        if (hasMedia)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            color: isDark ? Colors.grey[900] : Colors.grey[50],
            child: Row(
              children: [
                // Image preview
                if (_selectedImage != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _selectedImage!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedImage = null),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),

                // GIF preview
                if (_selectedGifUrl != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _selectedGifUrl!,
                          width: 80,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedGifUrl = null),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),

                const Spacer(),
                Text(
                  _selectedImage != null ? '📷 Image' : '🎞️ GIF',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

        // Input row with action buttons
        Container(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            8 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null
                    ? Icon(
                        Icons.person,
                        size: 18,
                        color: isDark ? Colors.grey[300] : Colors.grey[600],
                      )
                    : null,
              ),
              const SizedBox(width: 8),

              // Action buttons (image, GIF)
              GestureDetector(
                onTap: _selectedImage == null ? _pickImage : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.image_outlined,
                    size: 22,
                    color: _selectedImage != null
                        ? Theme.of(context).primaryColor
                        : Colors.grey[500],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _selectedGifUrl == null ? _pickGif : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.gif_box_outlined,
                    size: 22,
                    color: _selectedGifUrl != null
                        ? Colors.orange[600]
                        : Colors.grey[500],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Text field
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _inputFocusNode,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  decoration: InputDecoration(
                    hintText: _replyingToId != null
                        ? 'Write a reply...'
                        : 'Write a comment...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _postComment(),
                ),
              ),
              const SizedBox(width: 8),

              // Send button
              GestureDetector(
                onTap: _isPosting ? null : _postComment,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isPosting ? Colors.grey[300] : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
