import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/home/widgets/hangout_feed_card.dart';
import 'package:bitemates/features/home/widgets/social_post_card.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPost();
  }

  /// One RPC, the feed's exact row shape. This screen used to assemble the
  /// row by hand from a PostgREST select and the shape drifted from what
  /// SocialPostCard reads (`user` vs `user_data`, `like_count` vs
  /// `likes_count`, no top_likers, a comment count that was always 1) — so a
  /// shared post opened with a blank avatar, zero likes and no comments.
  Future<void> _fetchPost() async {
    try {
      final row = await SupabaseConfig.client.rpc(
        'get_post_by_id',
        params: {'p_post_id': widget.postId},
      );
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _error = 'This post is no longer available';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _post = Map<String, dynamic>.from(row as Map);
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching post: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load post';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _post == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Post not found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Determine type
    if (_post!['post_type'] == 'hangout') {
      return SingleChildScrollView(
        child: HangoutFeedCard(
          post: _post!,
          onTap:
              () {}, // No-op details or open modal? In detail screen, maybe no-op or full map
        ),
      );
    }

    return SingleChildScrollView(
      child: SocialPostCard(post: _post!),
    );
  }
}
