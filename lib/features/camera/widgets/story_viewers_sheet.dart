import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

/// Bottom sheet that displays who has viewed a story.
/// Only shown to the story author.
class StoryViewersSheet extends StatefulWidget {
  final String postId;
  final int initialCount;

  const StoryViewersSheet({
    super.key,
    required this.postId,
    this.initialCount = 0,
  });

  @override
  State<StoryViewersSheet> createState() => _StoryViewersSheetState();
}

class _StoryViewersSheetState extends State<StoryViewersSheet> {
  List<Map<String, dynamic>> _viewers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchViewers();
  }

  Future<void> _fetchViewers() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      // Step 1: Get viewer IDs and timestamps, excluding self
      var query = Supabase.instance.client
          .from('story_views')
          .select('viewer_id, viewed_at')
          .eq('post_id', widget.postId);

      if (currentUserId != null) {
        query = query.neq('viewer_id', currentUserId);
      }

      final viewsResponse = await query.order('viewed_at', ascending: false);

      final views = List<Map<String, dynamic>>.from(viewsResponse);
      if (views.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Step 2: Batch-fetch user profiles
      final viewerIds = views.map((v) => v['viewer_id'] as String).toList();
      final usersResponse = await Supabase.instance.client
          .from('users')
          .select('id, display_name, avatar_url, user_photos(photo_url, is_primary)')
          .inFilter('id', viewerIds);

      final usersMap = <String, Map<String, dynamic>>{};
      for (final u in List<Map<String, dynamic>>.from(usersResponse)) {
        usersMap[u['id'] as String] = u;
      }

      // Step 3: Merge
      final viewers = <Map<String, dynamic>>[];
      for (final v in views) {
        final user = usersMap[v['viewer_id']];
        String? avatarUrl = user?['avatar_url'] as String?;
        if (avatarUrl == null && user?['user_photos'] != null) {
          final photos = user!['user_photos'] as List;
          if (photos.isNotEmpty) {
            final primary = photos.firstWhere(
              (p) => p['is_primary'] == true,
              orElse: () => photos.first,
            );
            avatarUrl = primary['photo_url'] as String?;
          }
        }
        viewers.add({
          'viewer_id': v['viewer_id'],
          'viewed_at': v['viewed_at'],
          '_display_name': user?['display_name'] ?? 'Someone',
          '_avatar_url': avatarUrl,
        });
      }

      if (mounted) {
        setState(() {
          _viewers = viewers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching story viewers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.parse(timestamp);
    final diff = DateTime.now().toUtc().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Viewers',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isLoading
                        ? '${widget.initialCount}'
                        : '${_viewers.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            color: Colors.white.withOpacity(0.08),
          ),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.white54,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_viewers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: Colors.white.withOpacity(0.2),
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No viewers yet',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _viewers.length,
                itemBuilder: (context, index) {
                  final viewer = _viewers[index];
                  final name = viewer['_display_name'] ?? 'Someone';
                  final avatarUrl = viewer['_avatar_url'] as String?;
                  final viewedAt = viewer['viewed_at'] as String?;
                  final viewerId = viewer['viewer_id'] as String?;

                  return ListTile(
                    onTap: () {
                      if (viewerId != null) {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                UserProfileScreen(userId: viewerId),
                          ),
                        );
                      }
                    },
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      _formatTimeAgo(viewedAt),
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withOpacity(0.15),
                      size: 14,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
