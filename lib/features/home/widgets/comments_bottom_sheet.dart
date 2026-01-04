import 'package:flutter/material.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:bitemates/core/config/supabase_config.dart';

class CommentsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> post;

  const CommentsBottomSheet({super.key, required this.post});

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final Map<String, TextEditingController> _replyControllers = {};
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;
  String? _replyingTo; // Comment ID we're replying to

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    for (var controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final comments = await SocialService().getComments(widget.post['id']);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading comments: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final comment = await SocialService().addComment(
        postId: widget.post['id'],
        content: text,
      );

      if (comment != null && mounted) {
        setState(() {
          _comments.insert(0, comment);
          _isPosting = false;
        });
        _commentController.clear();
      }
    } catch (e) {
      print('Error posting comment: $e');
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _postReply(String parentId) async {
    final controller = _replyControllers[parentId];
    if (controller == null) return;

    final text = controller.text.trim();
    if (text.isEmpty) return;

    try {
      final reply = await SocialService().addComment(
        postId: widget.post['id'],
        content: text,
        parentId: parentId,
      );

      if (reply != null && mounted) {
        setState(() {
          // Find parent and add to replies (This assumes simplistic flat list or nesting)
          // For now, just add to the list and rely on UI to thread or re-fetch
          // Actually, adding to _comments list is flat.
          // Since UI iterates _comments, we should just load comments again or insert it gracefully?
          // Adding it flatly is fine for now if UI handles threading or we just refresh.
          // Correct implementation would insert it at right index or as nested property.
          // Let's simplified re-fetch or add to bottom for now.
          _comments.add(reply);
          _replyingTo = null;
        });
        controller.clear();
        _replyControllers.remove(parentId);
        _loadComments(); // Refresh to sort correctly or handle threading
      }
    } catch (e) {
      print('Error posting reply: $e');
    }
  }

  Future<void> _toggleLike(String commentId) async {
    await SocialService().toggleCommentLike(commentId);
    // Optimistic update logic could go here
    _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Comments List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      final isReply = comment['parent_id'] != null;
                      return _buildCommentCard(comment, isReply);
                    },
                  ),
          ),

          // Input Area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          const Expanded(
            child: Text(
              'Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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

  Widget _buildCommentCard(Map<String, dynamic> comment, bool isReply) {
    final timestamp = DateTime.tryParse(comment['created_at'] ?? '');
    final timeAgo = timestamp != null ? timeago.format(timestamp) : '';
    final user = comment['user'] as Map<String, dynamic>?;
    final userName = user?['display_name'] ?? 'User';
    final userAvatar = user?['avatar_url'] as String?;
    final isLiked = comment['is_liked'] ?? false;
    final likeCount = comment['like_count'] ?? 0;

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 48.0 : 0, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[300],
            backgroundImage: userAvatar != null
                ? NetworkImage(userAvatar)
                : null,
            child: userAvatar == null
                ? Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),

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
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment['content'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Actions row (Like, Reply, timestamp)
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Text(
                      timeAgo,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _toggleLike(comment['id']),
                      child: Text(
                        isLiked ? 'Liked' : 'Like',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isLiked ? Colors.blue : Colors.grey[700],
                        ),
                      ),
                    ),
                    if (likeCount > 0) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.thumb_up, size: 12, color: Colors.blue),
                      const SizedBox(width: 2),
                      Text(
                        '$likeCount',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                    const SizedBox(width: 16),
                    if (!isReply)
                      GestureDetector(
                        onTap: () => setState(() {
                          _replyingTo = comment['id'];
                          _replyControllers[comment['id']] =
                              TextEditingController();
                        }),
                        child: Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    // Delete option (only for comment owner)
                    if (comment['user_id'] ==
                        SupabaseConfig.client.auth.currentUser?.id) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Comment'),
                              content: const Text(
                                'Are you sure you want to delete this comment?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true && mounted) {
                            final success = await SocialService().deleteComment(
                              comment['id'],
                            );
                            if (success && mounted) {
                              setState(() {
                                _comments.removeWhere(
                                  (c) => c['id'] == comment['id'],
                                );
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Comment deleted'),
                                  ),
                                );
                              }
                            }
                          }
                        },
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

                // Reply input (if replying to this comment)
                if (_replyingTo == comment['id'])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildReplyInput(comment['id']),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyInput(String parentId) {
    final controller = _replyControllers[parentId]!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Write a reply...',
              hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: Colors.blue),
          onPressed: () => _postReply(parentId),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    final currentUser = SupabaseConfig.client.auth.currentUser;
    final userMetadata = currentUser?.userMetadata;
    final avatarUrl = userMetadata?['avatar_url'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[300],
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? const Icon(Icons.person, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Write a comment...',
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[100],
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
          IconButton(
            icon: Icon(
              Icons.send,
              color: _isPosting ? Colors.grey : Colors.blue,
            ),
            onPressed: _isPosting ? null : _postComment,
          ),
        ],
      ),
    );
  }
}
