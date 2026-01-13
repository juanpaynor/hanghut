import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';

class SocialPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;

  const SocialPostCard({super.key, required this.post, this.onTap});

  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  late bool _isLiked;
  late int _likeCount;
  late int _commentCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['is_liked'] ?? false;
    _likeCount = widget.post['like_count'] ?? 0;
    _commentCount = widget.post['comment_count'] ?? 0;
  }

  void _handleLike() {
    // Optimistic Update
    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999);
      } else {
        _isLiked = true;
        _likeCount++;
      }
    });
    // Call Service
    SocialService().togglePostLike(widget.post['id']);
  }

  @override
  Widget build(BuildContext context) {
    // Extract data from Supabase post
    final content = widget.post['content'] as String? ?? '';
    final imageUrl = widget.post['image_url'] as String?;
    final imageUrls = widget.post['image_urls'] as List?;
    final createdAt = widget.post['created_at'] as String?;
    final user = widget.post['user'] as Map<String, dynamic>?;
    final displayName = user?['display_name'] ?? 'User';
    final avatarUrl = user?['avatar_url'] as String?;

    // Convert image_urls to List<String> if present, otherwise use single image_url
    final List<String> images = [];
    if (imageUrls != null && imageUrls.isNotEmpty) {
      images.addAll(imageUrls.map((url) => url.toString()));
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      images.add(imageUrl);
    }

    // Parse timestamp
    DateTime? postTime;
    if (createdAt != null) {
      try {
        postTime = DateTime.parse(createdAt);
      } catch (e) {
        print('Error parsing timestamp: $e');
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row (Avatar + Name + Time)
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[100],
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          if (postTime != null)
                            Text(
                              timeago.format(postTime),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // More options menu (only show for post owner)
                    if (widget.post['user_id'] ==
                        SupabaseConfig.client.auth.currentUser?.id)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz, color: Colors.grey[400]),
                        onSelected: (value) async {
                          if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Post'),
                                content: const Text(
                                  'Are you sure you want to delete this post?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true && context.mounted) {
                              // Import SocialService at top of file
                              final success = await SocialService().deletePost(
                                widget.post['id'],
                              );
                              if (success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post deleted')),
                                );
                                // Notify parent to refresh
                                if (widget.onTap != null) widget.onTap!();
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Delete Post',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      Icon(Icons.more_horiz, color: Colors.grey[300]),
                  ],
                ),

                const SizedBox(height: 12),

                // Post Text
                if (content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),

                // Post Images (Carousel if multiple)
                if (images.isNotEmpty) ...[
                  images.length == 1
                      ? _buildSingleImage(images.first)
                      : _buildImageCarousel(images),
                  const SizedBox(height: 12),
                ],

                // Action Buttons (Like, Comment)
                Row(
                  children: [
                    _buildActionButton(
                      icon: _isLiked
                          ? Icons.favorite
                          : Icons.favorite_border_rounded,
                      label: _likeCount > 0 ? '$_likeCount' : 'Like',
                      onTap: _handleLike,
                      color: _isLiked ? Colors.red : Colors.grey[600]!,
                      activeColor: Colors.red,
                    ),
                    const SizedBox(width: 20),
                    _buildActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      label:
                          widget.post['comment_count'] != null &&
                              widget.post['comment_count'] > 0
                          ? '${widget.post['comment_count']}'
                          : 'Comment',
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) =>
                              CommentsBottomSheet(post: widget.post),
                        ).then((_) {
                          // Refresh to update comment count
                          if (widget.onTap != null) widget.onTap!();
                        });
                      },
                      color: Colors.grey[600],
                      activeColor: Colors.blueAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleImage(String url) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenImageViewer(imageUrl: url),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: url,
          width: double.infinity,
          height: 250,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => _buildErrorImage(),
        ),
      ),
    );
  }

  Widget _buildImageCarousel(List<String> imageUrls) {
    return SizedBox(
      height: 250,
      child: PageView.builder(
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FullScreenImageViewer(imageUrl: imageUrls[index]),
                      ),
                    );
                  },
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[index],
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => _buildErrorImage(),
                  ),
                ),
              ),
              // Page indicator
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${index + 1}/${imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorImage() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: Colors.grey[400],
          size: 40,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Color? activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: activeColor != null && color == Colors.red
                  ? activeColor
                  : (color ?? Colors.grey[600]),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color ?? Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
