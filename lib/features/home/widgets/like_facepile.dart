import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

/// Instagram-style "who liked this" row: overlapping avatars + summary text.
/// Works for both feed posts and stories (they share the `post_likes` table).
///
/// Renders nothing when [likeCount] is 0. Tapping opens the full likers sheet.
class LikeFacepile extends StatefulWidget {
  final String postId;
  final int likeCount;

  /// When true, avatars/text render in light colors for dark backgrounds
  /// (e.g. the full-screen story viewer).
  final bool onDark;

  /// Preview likers (up to 3) already embedded in the source payload — e.g. the
  /// feed RPC's `top_likers`. When provided, the pile renders from these with NO
  /// network call (avoids an N+1 across the feed). When null, it lazily fetches.
  /// Each map: {user_id, display_name, avatar_url}.
  final List<Map<String, dynamic>>? initialLikers;

  const LikeFacepile({
    super.key,
    required this.postId,
    required this.likeCount,
    this.onDark = false,
    this.initialLikers,
  });

  @override
  State<LikeFacepile> createState() => _LikeFacepileState();
}

class _LikeFacepileState extends State<LikeFacepile> {
  List<Map<String, dynamic>> _likers = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _initOrLoad();
  }

  @override
  void didUpdateWidget(LikeFacepile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh the preview when the like count changes (someone liked/unliked)
    // or the source likers change.
    if (oldWidget.likeCount != widget.likeCount ||
        oldWidget.postId != widget.postId ||
        oldWidget.initialLikers != widget.initialLikers) {
      _initOrLoad();
    }
  }

  /// Use embedded likers when supplied (no fetch); otherwise lazily load.
  /// Assigns fields directly — a build always follows initState/didUpdateWidget;
  /// _load() manages its own setState for the async result.
  void _initOrLoad() {
    if (widget.initialLikers != null) {
      _likers = widget.initialLikers!;
      _loaded = true;
    } else if (widget.likeCount > 0) {
      _likers = [];
      _loaded = false;
      _load();
    } else {
      _likers = [];
      _loaded = false;
    }
  }

  Future<void> _load() async {
    final likers = await SocialService().getPostLikers(widget.postId, limit: 10);
    if (!mounted) return;
    setState(() {
      _likers = likers;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.likeCount <= 0) return const SizedBox.shrink();

    final Color textColor = widget.onDark ? Colors.white : Colors.grey[800]!;
    final Color subtleColor =
        widget.onDark ? Colors.white70 : Colors.grey[600]!;

    // Number of avatars to show in the pile.
    final faces = _likers.take(3).toList();

    return InkWell(
      onTap: () => showPostLikesSheet(context, widget.postId),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (faces.isNotEmpty) ...[
              SizedBox(
                width: 20.0 + (faces.length - 1) * 14.0,
                height: 24,
                child: Stack(
                  children: [
                    for (int i = 0; i < faces.length; i++)
                      Positioned(
                        left: i * 14.0,
                        child: _Avatar(
                          url: faces[i]['avatar_url'] as String?,
                          name: faces[i]['display_name'] as String?,
                          ringColor: widget.onDark ? Colors.black : Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: subtleColor),
                  children: _summarySpans(textColor, subtleColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _summarySpans(Color textColor, Color subtleColor) {
    final count = widget.likeCount;
    // Before likers load, fall back to a plain count so there's no flicker.
    if (!_loaded || _likers.isEmpty) {
      return [
        TextSpan(text: 'Liked by '),
        TextSpan(
          text: '$count ${count == 1 ? 'person' : 'people'}',
          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        ),
      ];
    }

    final firstName =
        (_likers.first['display_name'] as String?)?.trim().isNotEmpty == true
        ? _likers.first['display_name'] as String
        : '@${_likers.first['username'] ?? 'someone'}';
    final others = count - 1;

    return [
      const TextSpan(text: 'Liked by '),
      TextSpan(
        text: firstName,
        style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
      ),
      if (others > 0) ...[
        const TextSpan(text: ' and '),
        TextSpan(
          text: '$others ${others == 1 ? 'other' : 'others'}',
          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        ),
      ],
    ];
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String? name;
  final Color ringColor;
  final double size;

  const _Avatar({
    required this.url,
    required this.name,
    required this.ringColor,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final initial = (name?.trim().isNotEmpty == true)
        ? name!.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 1.5),
        color: AppTheme.primaryColor.withOpacity(0.15),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _initialFallback(initial),
              placeholder: (_, __) => _initialFallback(initial),
            )
          : _initialFallback(initial),
    );
  }

  Widget _initialFallback(String initial) => Center(
    child: Text(
      initial,
      style: TextStyle(
        fontSize: size * 0.45,
        fontWeight: FontWeight.w700,
        color: AppTheme.primaryColor,
      ),
    ),
  );
}

/// Full list of everyone who liked a post/story.
Future<void> showPostLikesSheet(BuildContext context, String postId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostLikesSheet(postId: postId),
  );
}

class _PostLikesSheet extends StatefulWidget {
  final String postId;
  const _PostLikesSheet({required this.postId});

  @override
  State<_PostLikesSheet> createState() => _PostLikesSheetState();
}

class _PostLikesSheetState extends State<_PostLikesSheet> {
  List<Map<String, dynamic>>? _likers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final likers = await SocialService().getPostLikers(widget.postId, limit: 200);
    if (!mounted) return;
    setState(() => _likers = likers);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Likes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[200]),
              Expanded(child: _body(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(ScrollController controller) {
    if (_likers == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likers!.isEmpty) {
      return Center(
        child: Text('No likes yet', style: TextStyle(color: Colors.grey[500])),
      );
    }
    return ListView.builder(
      controller: controller,
      itemCount: _likers!.length,
      itemBuilder: (context, i) {
        final u = _likers![i];
        final name = (u['display_name'] as String?)?.trim();
        final username = u['username'] as String?;
        return ListTile(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: u['user_id']),
              ),
            );
          },
          leading: SizedBox(
            width: 44,
            height: 44,
            child: _Avatar(
              url: u['avatar_url'] as String?,
              name: name,
              ringColor: Colors.transparent,
              size: 44,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name?.isNotEmpty == true
                      ? name!
                      : (username != null ? '@$username' : 'User'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (u['is_verified_photo'] == true) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, size: 15, color: Colors.blue),
              ],
            ],
          ),
          subtitle: (username != null && name?.isNotEmpty == true)
              ? Text('@$username',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12))
              : null,
        );
      },
    );
  }
}
