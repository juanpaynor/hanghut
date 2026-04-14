import 'package:flutter/material.dart';

import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/features/home/widgets/edit_post_modal.dart';

class HangoutFeedCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  final Function(String)? onPostDeleted;
  final ValueChanged<Map<String, dynamic>>? onPostEdited;

  const HangoutFeedCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onPostDeleted,
    this.onPostEdited,
  });

  @override
  State<HangoutFeedCard> createState() => _HangoutFeedCardState();
}

class _HangoutFeedCardState extends State<HangoutFeedCard> {
  late bool _isLiked;
  late int _likeCount;
  String? _asyncTitle;
  String? _asyncDescription;
  String? _liveTableStatus; // Live status fetched from DB
  bool _tableExists = true; // False if the table was deleted

  @override
  void initState() {
    super.initState();
    _isLiked =
        widget.post['is_liked'] ?? widget.post['user_has_liked'] ?? false;
    _likeCount = widget.post['like_count'] ?? widget.post['likes_count'] ?? 0;
    _fetchTableDetailsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant HangoutFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync like state when parent rebuilds with fresh data (e.g. pull-to-refresh)
    if (oldWidget.post['id'] != widget.post['id']) {
      _isLiked =
          widget.post['is_liked'] ?? widget.post['user_has_liked'] ?? false;
      _likeCount = widget.post['like_count'] ?? widget.post['likes_count'] ?? 0;
    }
  }

  /// Fetch the real title/description from the `tables` row
  /// when the post metadata doesn't have them (old posts).
  Future<void> _fetchTableDetailsIfNeeded() async {
    final metadata = widget.post['metadata'] as Map<String, dynamic>? ?? {};
    final tableId = metadata['table_id'];

    // Only fetch if metadata is missing title AND we have a table_id
    if (tableId != null && metadata['title'] == null) {
      try {
        final result = await SupabaseConfig.client
            .from('tables')
            .select('title, description, status')
            .eq('id', tableId)
            .maybeSingle();

        if (mounted) {
          if (result == null) {
            // Table was deleted — treat as ended
            setState(() => _tableExists = false);
          } else {
            setState(() {
              _asyncTitle = result['title'];
              _asyncDescription = result['description'];
              _liveTableStatus = result['status'];
            });
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching table details for feed card: $e');
      }
    } else if (tableId != null) {
      // We have a table_id and title, still fetch live status
      try {
        final result = await SupabaseConfig.client
            .from('tables')
            .select('status')
            .eq('id', tableId)
            .maybeSingle();

        if (mounted) {
          if (result == null) {
            // Table was deleted
            setState(() => _tableExists = false);
          } else {
            setState(() => _liveTableStatus = result['status']);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching table status for feed card: $e');
      }
    }
  }

  void _handleLike() async {
    final wasLiked = _isLiked;
    final prevCount = _likeCount;

    // Optimistic update
    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999);
      } else {
        _isLiked = true;
        _likeCount++;
      }
    });

    // Await service — revert on failure
    try {
      final result = await SocialService().togglePostLike(widget.post['id']);
      // If the guard rejected it (concurrent tap), revert
      if (result == false && !wasLiked) {
        // Service returned false but we expected a like — could be guard rejection
        // Only revert if the guard blocked it (count didn't change)
      }
    } catch (e) {
      // Revert optimistic update
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount = prevCount;
        });
      }
    }
  }

  Future<void> _handleComment() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsBottomSheet(post: widget.post),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.post['user'];
    final createdAt = DateTime.parse(widget.post['created_at']);
    final metadata = widget.post['metadata'] as Map<String, dynamic>? ?? {};

    final venueName = metadata['venue_name'] ?? 'Unknown Venue';
    final customTitle = _asyncTitle ?? metadata['title'] ?? venueName;
    final currentDesc = _asyncDescription ?? metadata['description'];
    final activityType = metadata['activity_type'] ?? 'Hangout';
    final imageUrl = metadata['image_url'];
    final videoUrl = metadata['video_url'] as String?;
    final scheduledTimeStr = metadata['scheduled_time'];
    final scheduledTime = scheduledTimeStr != null
        ? DateTime.parse(scheduledTimeStr)
        : null;

    final commentCount = widget.post['comment_count'] ?? 0;

    // Extract filter info from metadata
    final rawFilters = metadata['filters'];
    final filters = rawFilters is Map ? Map<String, dynamic>.from(rawFilters) : <String, dynamic>{};
    final metaVisibility = metadata['visibility'] as String? ?? 'public';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Theme.of(context).cardColor,
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header (User Info + Badge)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (user != null && user['id'] != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserProfileScreen(userId: user['id']),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: user?['avatar_url'] != null
                        ? NetworkImage(user!['avatar_url']) as ImageProvider
                        : null,
                    child: user?['avatar_url'] == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['display_name'] ?? 'Someone',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _getActivityDescription(activityType),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 13,
                        ),
                      ),
                      if (currentDesc != null &&
                          currentDesc.toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Linkify(
                          onOpen: (link) async {
                            final Uri uri = Uri.parse(link.url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          text: currentDesc.toString(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
                            fontSize: 13,
                          ),
                          linkStyle: const TextStyle(color: Colors.blue),
                        ),
                      ],
                    ],
                  ),
                ),
                // 3-dot menu for owner, 'New' badge for others
                if (widget.post['user_id'] ==
                    SupabaseConfig.client.auth.currentUser?.id)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: Colors.grey[400]),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final result = await Navigator.of(context)
                            .push<Map<String, dynamic>?>(
                              PageRouteBuilder(
                                opaque: false,
                                barrierDismissible: true,
                                barrierColor: Colors.black54,
                                transitionDuration: const Duration(
                                  milliseconds: 300,
                                ),
                                reverseTransitionDuration: const Duration(
                                  milliseconds: 250,
                                ),
                                pageBuilder:
                                    (context, animation, secondaryAnimation) {
                                      return EditPostModal(post: widget.post);
                                    },
                                transitionsBuilder:
                                    (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) {
                                      return FadeTransition(
                                        opacity: CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOut,
                                        ),
                                        child: child,
                                      );
                                    },
                              ),
                            );
                        if (result != null && mounted) {
                          widget.onPostEdited?.call(result);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Post updated')),
                          );
                        }
                      } else if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Hangout Post'),
                            content: const Text(
                              'Are you sure you want to delete this hangout post?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          final success = await SocialService().deletePost(
                            widget.post['id'],
                          );
                          if (success && context.mounted) {
                            widget.onPostDeleted?.call(widget.post['id']);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post deleted')),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, color: Colors.black87),
                            SizedBox(width: 8),
                            Text('Edit Post'),
                          ],
                        ),
                      ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.celebration,
                          size: 14,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'New',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 2. Main Content (Image/Map + Details)
          if (imageUrl != null) ...[
            // Image present: show full uncropped image (clean, no text overlay)
            GestureDetector(
              onTap: () {
                if (videoUrl != null && videoUrl.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _HangoutVideoPlayer(videoUrl: videoUrl),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FullScreenImageViewer(imageUrl: imageUrl),
                    ),
                  );
                }
              },
              child: Stack(
                children: [
                  // Full-width uncropped image
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    placeholder: (context, url) => Container(
                      height: 220,
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 220,
                      color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.broken_image, size: 40)),
                    ),
                  ),
                  // Video play button only
                  if (videoUrl != null && videoUrl.isNotEmpty)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.black87),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Details section below the image
            InkWell(
              onTap: _isTableEnded ? null : widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (currentDesc != null &&
                              currentDesc.toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                currentDesc.toString(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  venueName,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (scheduledTime != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('EEE, MMM d • h:mm a').format(scheduledTime),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Join button
                    _buildJoinButton(metadata),
                  ],
                ),
              ),
            ),
          ] else ...[
            // No image: show Mapbox static map preview with indigo pin (or gradient fallback)
            Builder(builder: (context) {
              final lat = widget.post['latitude'];
              final lng = widget.post['longitude'];
              final mapboxToken = dotenv.env['MAPBOX_PUBLIC_TOKEN'];
              final hasCoords = lat != null && lng != null && mapboxToken != null;

              if (hasCoords) {
                // Mapbox Static Images API with indigo pin
                final staticMapUrl =
                    'https://api.mapbox.com/styles/v1/mapbox/light-v11/static/'
                    'pin-l+3F51B5($lng,$lat)/$lng,$lat,15,0/600x400@2x'
                    '?access_token=$mapboxToken';

                return GestureDetector(
                  onTap: _isTableEnded ? null : widget.onTap,
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: staticMapUrl,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 220,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
                            ),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.indigo,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 220,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2A0845), Color(0xFF6441A5)],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.location_on, size: 48, color: Colors.white70),
                          ),
                        ),
                      ),
                      // Subtle bottom gradient for readability
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.4),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Activity Type Badge
                      Positioned(
                        top: 12, left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.indigo,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            activityType.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold,
                              fontSize: 10, letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Fallback: no coordinates — show gradient
              return GestureDetector(
                onTap: _isTableEnded ? null : widget.onTap,
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A0845), Color(0xFF6441A5)],
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.location_on, size: 48, color: Colors.white70),
                  ),
                ),
              );
            }),
            // Details section below the map preview
            InkWell(
              onTap: _isTableEnded ? null : widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (currentDesc != null &&
                              currentDesc.toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                currentDesc.toString(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  venueName,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (scheduledTime != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('EEE, MMM d • h:mm a').format(scheduledTime),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildJoinButton(metadata),
                  ],
                ),
              ),
            ),
          ],

     // 3. Filter Chips Row (between content and social actions)
         if (filters.isNotEmpty || metaVisibility == 'followers_only')
           Padding(
             padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
             child: _buildFilterChips(filters, metaVisibility),
           ),

         // 4. Social Actions Row (Like & Comment)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
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
                  label: commentCount > 0 ? '$commentCount' : 'Comment',
                  onTap: _handleComment,
                  color: Colors.grey[600],
                  activeColor: Colors.blueAccent,
                ),
                const Spacer(),
                // Time ago
                Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  timeago.format(createdAt),
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
  ],
);
  }

  Widget _buildOverlayDetails(String customTitle, dynamic currentDesc, String venueName, DateTime? scheduledTime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          customTitle,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        if (currentDesc != null && currentDesc.toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
            child: Text(
              currentDesc.toString(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 13,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.location_on, color: Colors.white.withOpacity(0.9), size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                venueName,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w500,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (scheduledTime != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.white.withOpacity(0.9), size: 14),
              const SizedBox(width: 4),
              Text(
                DateFormat('EEE, MMM d • h:mm a').format(scheduledTime),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9), fontSize: 13,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFilterChips(Map<String, dynamic> filters, String visibility) {
    final chips = <Widget>[];

    // Visibility
    if (visibility == 'followers_only') {
      chips.add(_filterChip('👥 Followers Only', Colors.purple));
    }

    // Gender
    final gender = filters['gender'] as String?;
    if (gender != null && gender != 'everyone') {
      String label;
      switch (gender) {
        case 'women_only':
          label = '👩 Women Only';
          break;
        case 'men_only':
          label = '👨 Men Only';
          break;
        case 'nonbinary_only':
          label = '🏳️‍🌈 Non-binary Only';
          break;
        default:
          label = gender;
      }
      chips.add(_filterChip(label, Colors.pink));
    }

    // Age range
    final ageMin = filters['age_min'];
    final ageMax = filters['age_max'];
    if (ageMin != null || ageMax != null) {
      chips.add(_filterChip('🔞 ${ageMin ?? 18}–${ageMax ?? 65}', Colors.orange));
    }

    // Enforcement
    final enforcement = filters['enforcement'] as String?;
    if (enforcement == 'hard' && chips.isNotEmpty) {
      chips.add(_filterChip('🔒 Enforced', Colors.red));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _filterChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  bool get _isTableEnded {
    // 1. Table was deleted from DB
    if (!_tableExists) return true;

    // 2. Scheduled time has passed — most reliable check
    final metadata = widget.post['metadata'] as Map<String, dynamic>? ?? {};
    final scheduledTimeStr = metadata['scheduled_time'] as String?;
    if (scheduledTimeStr != null) {
      final scheduledTime = DateTime.tryParse(scheduledTimeStr);
      if (scheduledTime != null && DateTime.now().isAfter(scheduledTime)) return true;
    }

    // 3. DB status column explicitly set to non-open
    final status = _liveTableStatus ?? metadata['status'];
    if (status != null && status != 'open') return true;

    return false;
  }

  Widget _buildJoinButton(Map<String, dynamic> metadata) {
    if (_isTableEnded) {
      return Text(
        'Activity Done',
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return ElevatedButton(
      onPressed: widget.onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  String _getActivityDescription(String type) {
    return 'created an event';
  }

  String _getEmojiForActivity(String activityType) {
    final lower = activityType.toLowerCase();
    if (lower.contains('coffee')) return '☕';
    if (lower.contains('drink') || lower.contains('bar')) return '🍸';
    if (lower.contains('dine') ||
        lower.contains('food') ||
        lower.contains('eat'))
      return '🍽️';
    if (lower.contains('movie') || lower.contains('film')) return '🍿';
    if (lower.contains('music') || lower.contains('concert')) return '🎵';
    if (lower.contains('sport') || lower.contains('active')) return '🏃';
    if (lower.contains('party') || lower.contains('club')) return '🪩';
    if (lower.contains('game')) return '🎲';
    if (lower.contains('explore') || lower.contains('walk')) return '🌆';
    return '👋'; // Default
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

/// Full-screen video player for hangout feed cards
class _HangoutVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const _HangoutVideoPlayer({required this.videoUrl});

  @override
  State<_HangoutVideoPlayer> createState() => _HangoutVideoPlayerState();
}

class _HangoutVideoPlayerState extends State<_HangoutVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
          _controller.setLooping(true);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () {
          setState(() {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
          });
        },
        child: Center(
          child: _isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      if (!_controller.value.isPlaying)
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
