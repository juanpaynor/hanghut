import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/home/widgets/event_attachment_card.dart';
import 'package:bitemates/features/ticketing/screens/event_purchase_screen.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

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
  bool _isAnimatingLike = false;
  Map<String, dynamic>? _attachedEvent;
  bool _isLoadingEvent = false;
  late int _commentCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['user_has_liked'] ?? false;
    _likeCount = widget.post['likes_count'] ?? 0;
    _commentCount = widget.post['comment_count'] ?? 0;
    _fetchAttachedEvent();
  }

  Future<void> _fetchAttachedEvent() async {
    final eventId = widget.post['event_id'];
    // print('🔍 [SocialPostCard] Post ${widget.post['id']} has eventId: $eventId');

    if (eventId != null) {
      if (mounted) setState(() => _isLoadingEvent = true);
      try {
        final data = await SupabaseConfig.client
            .from('events')
            .select('*')
            .eq('id', eventId)
            .single();
        // print('✅ [SocialPostCard] Fetched event data: ${data['title']}');

        if (mounted) setState(() => _attachedEvent = data);
      } catch (e) {
        print('❌ [SocialPostCard] Error fetching event $eventId: $e');
      } finally {
        if (mounted) setState(() => _isLoadingEvent = false);
      }
    }
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
    final gifUrl = widget.post['gif_url'] as String?;
    final createdAt = widget.post['created_at'] as String?;
    final user = widget.post['user'] as Map<String, dynamic>?;
    final displayName = user?['display_name'] ?? 'User';
    final avatarUrl = user?['avatar_url'] as String?;

    // Convert image_urls to List<String> if present, otherwise use single image_url
    // Only show images if there's no GIF (mutually exclusive)
    final List<String> images = [];
    if (gifUrl == null || gifUrl.isEmpty) {
      if (imageUrls != null && imageUrls.isNotEmpty) {
        images.addAll(imageUrls.map((url) => url.toString()));
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        images.add(imageUrl);
      }
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
                    GestureDetector(
                      onTap: () {
                        // Navigate to user profile
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: widget.post['user_id'],
                            ),
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[100],
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
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

                // Event Attachment
                if (_attachedEvent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EventAttachmentCard(
                      event: _attachedEvent!,
                      onTap: () {
                        try {
                          // Add defaults for potentially missing fields
                          final eventData = Map<String, dynamic>.from(
                            _attachedEvent!,
                          );

                          // Ensure required fields have defaults
                          eventData['venue_address'] ??=
                              eventData['venue_name'] ?? 'TBA';
                          eventData['category'] ??= 'general';
                          eventData['created_at'] ??= DateTime.now()
                              .toIso8601String();
                          eventData['tickets_sold'] ??= 0;

                          // Convert Map to Event model
                          final event = Event.fromJson(eventData);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventPurchaseScreen(event: event),
                            ),
                          );
                        } catch (e) {
                          print('Error parsing event: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open event: $e')),
                          );
                        }
                      },
                      onImageTap: () {
                        final imageUrl = _attachedEvent!['cover_image_url'];
                        if (imageUrl != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FullScreenImageViewer(imageUrl: imageUrl),
                            ),
                          );
                        }
                      },
                    ),
                  )
                else if (widget.post['event_id'] != null && _isLoadingEvent)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),

                // Post Images (Grid Collage for multiple, single for one)
                if (images.isNotEmpty) ...[
                  _buildImageCollage(images),
                  const SizedBox(height: 12),
                ],

                // GIF Display (mutually exclusive with images)
                if (gifUrl != null && gifUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      gifUrl,
                      width: double.infinity,
                      height: 250,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 250,
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 250,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.gif_box_outlined,
                              color: Colors.grey[400],
                              size: 40,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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
                        );
                        // ✅ Removed .then() reload - feed state persists now
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

  /// Build collage grid for images (Instagram/Facebook style)
  Widget _buildImageCollage(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // Single image - full width
    if (imageUrls.length == 1) {
      return GestureDetector(
        onTap: () => _openImageViewer(imageUrls, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: imageUrls[0],
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

    // Two images - side by side
    if (imageUrls.length == 2) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 250,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openImageViewer(imageUrls, 0),
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[0],
                    height: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openImageViewer(imageUrls, 1),
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[1],
                    height: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Three images - 1 large on left, 2 stacked on right
    if (imageUrls.length == 3) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 250,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => _openImageViewer(imageUrls, 0),
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[0],
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openImageViewer(imageUrls, 1),
                        child: CachedNetworkImage(
                          imageUrl: imageUrls[1],
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openImageViewer(imageUrls, 2),
                        child: CachedNetworkImage(
                          imageUrl: imageUrls[2],
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Four+ images - 2x2 grid, with "+X" overlay for more
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 250,
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 0),
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[0],
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 2),
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[2],
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 1),
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[1],
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 3),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: imageUrls[3],
                            fit: BoxFit.cover,
                          ),
                          if (imageUrls.length > 4)
                            Container(
                              color: Colors.black.withOpacity(0.6),
                              child: Center(
                                child: Text(
                                  '+${imageUrls.length - 4}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImageViewer(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          imageUrl: images[initialIndex],
          imageUrls: images,
          initialIndex: initialIndex,
        ),
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
