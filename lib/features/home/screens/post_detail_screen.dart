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

  Future<void> _fetchPost() async {
    try {
      // Manual Construct
      final postData = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            user:user_id (
              id,
              display_name,
              avatar_url
            ),
            post_likes (user_id),
            comments (count)
          ''')
          .eq('id', widget.postId)
          .single();

      // Transform to match Feed format
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      final likes = postData['post_likes'] as List;

      final formattedPost = {
        ...postData,
        'like_count': likes.length,
        'is_liked': likes.any((l) => l['user_id'] == userId),
        'comment_count': (postData['comments'] as List).length, // simple count
      };

      if (mounted) {
        setState(() {
          _post = formattedPost;
          _isLoading = false;
        });
      }
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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SocialPostCard(post: _post!),
      ),
    );
  }
}
