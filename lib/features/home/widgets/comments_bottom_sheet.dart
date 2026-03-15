import 'package:flutter/material.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

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
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 50;

  // Reply state
  String? _replyingToId;
  String? _replyingToName;

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
  }

  @override
  void dispose() {
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
    if (text.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final postId = widget.post['id']?.toString();
      if (postId == null || postId.isEmpty) return;

      final comment = await SocialService().addComment(
        postId: postId,
        content: text,
        parentId: _replyingToId,
      );

      if (comment != null && mounted) {
        _commentController.clear();
        _clearReplyState();
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
                        Text(
                          comment['content'] ?? '',
                          style: const TextStyle(fontSize: 14, height: 1.3),
                        ),
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

  Widget _buildInputArea() {
    final currentUser = SupabaseConfig.client.auth.currentUser;
    final userMetadata = currentUser?.userMetadata;
    final avatarUrl = userMetadata?['avatar_url'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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

        // Input
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.of(context).viewInsets.bottom,
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
              const SizedBox(width: 10),
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
              GestureDetector(
                onTap: _isPosting ? null : _postComment,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isPosting ? Colors.grey[300] : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
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
