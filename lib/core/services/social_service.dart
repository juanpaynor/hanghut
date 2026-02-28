import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:h3_flutter/h3_flutter.dart';

class SocialService {
  static final SocialService _instance = SocialService._internal();
  factory SocialService() => _instance;
  SocialService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  Future<Map<String, dynamic>> getFeed({
    int limit = 20,
    int offset = 0,
    String? cursor, // Cursor timestamp for cursor-based pagination
    String? cursorId, // Cursor ID for tie-breaking
    bool useCursor = true, // Default to cursor mode
    bool followingOnly = false, // New: Filter by following
    double? userLat,
    double? userLng,
  }) async {
    try {
      final Map<String, dynamic> params;
      final String rpcName;

      if (useCursor) {
        if (followingOnly) {
          // ✅ Use Following Feed RPC
          params = {
            'p_limit': limit + 1,
            'p_cursor': cursor,
            'p_cursor_id': cursorId,
            'p_user_lat': userLat,
            'p_user_lng': userLng,
          };
          rpcName = 'get_following_feed';
        } else {
          // ✅ Use Philippines-wide RPC (no H3 filtering)
          params = {
            'p_limit': limit + 1,
            'p_cursor': cursor,
            'p_cursor_id': cursorId,
            'p_user_lat': userLat,
            'p_user_lng': userLng,
          };
          rpcName = 'get_philippines_feed'; // ✅ Nationwide coverage
        }
      } else {
        // Offset-based pagination (backwards compatibility with H3)
        List<String>? h3Cells;
        if (userLat != null && userLng != null) {
          h3Cells = getH3CellsForLocation(userLat, userLng);
        }

        params = {
          'p_limit': limit + 1,
          'p_offset': offset,
          'p_user_lat': userLat,
          'p_user_lng': userLng,
          'p_h3_cells': h3Cells,
        };
        rpcName = 'get_main_feed';
      }

      print('🔍 Calling RPC: $rpcName with params: $params');
      final response = await _client.rpc(rpcName, params: params);
      print(
        '📦 Response received: ${response?.toString().substring(0, 100)}...',
      );

      // Handle response - it might be null or empty
      if (response == null) {
        return {
          'posts': [],
          'hasMore': false,
          'nextCursor': null,
          'nextCursorId': null,
        };
      }

      // Cast to List first
      final responseList = response is List ? response : [response];

      // Map each item to Map<String, dynamic>
      final List<Map<String, dynamic>> posts = responseList
          .map((item) {
            if (item is Map<String, dynamic>) {
              return item;
            } else if (item is Map) {
              // Convert Map to Map<String, dynamic>
              return Map<String, dynamic>.from(item);
            } else {
              print('⚠️ Unexpected item type: ${item.runtimeType}');
              return <String, dynamic>{};
            }
          })
          .where((item) => item.isNotEmpty)
          .toList();

      // Map RPC result back to expected format
      final mappedPosts = posts.map((post) {
        // user_data comes as JSONB from RPC, ensure it's a Map
        final userData = post['user_data'] as Map<String, dynamic>? ?? {};

        return {
          ...post,
          'user': userData,
          // Counts and is_liked are already calculated by RPC
        };
      }).toList();

      // Extract metadata for cursor mode
      bool hasMore = false;
      String? nextCursor;
      String? nextCursorId;

      if (responseList.length > limit) {
        hasMore = true;
        final lastItem = mappedPosts[limit - 1];
        nextCursor = lastItem['created_at'];
        nextCursorId = lastItem['id'];

        // Remove the extra item fetched for pagination check
        mappedPosts.removeLast();
      }

      return {
        'posts': mappedPosts,
        'hasMore': hasMore,
        'nextCursor': nextCursor,
        'nextCursorId': nextCursorId,
      };
    } catch (e) {
      print('Error fetching feed: $e');
      rethrow;
    }
  }

  /// Create a new post with up to 5 images
  Future<Map<String, dynamic>?> createPost({
    required String content,
    List<File>? imageFiles,
    String? gifUrl,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      // Validate max 5 images
      if (imageFiles != null && imageFiles.length > 5) {
        throw Exception('Maximum 5 images allowed');
      }

      // Calculate H3 cell from location
      String? h3Cell;
      if (latitude != null && longitude != null) {
        h3Cell = _calculateH3Cell(latitude, longitude);
      }

      List<String>? imageUrls;

      // 1. Upload Images in parallel (much faster!)
      if (imageFiles != null && imageFiles.isNotEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        // Create upload futures for all images
        final uploadFutures = imageFiles.asMap().entries.map((entry) async {
          final index = entry.key;
          final imageFile = entry.value;
          final fileExt = imageFile.path.split('.').last;
          final fileName = '${timestamp}_${userId}_$index.$fileExt';
          final filePath = 'posts/$fileName';

          await _client.storage
              .from('social_images')
              .upload(
                filePath,
                imageFile,
                fileOptions: const FileOptions(
                  cacheControl: '3600',
                  upsert: false,
                ),
              );

          return _client.storage.from('social_images').getPublicUrl(filePath);
        });

        // Wait for all uploads to complete in parallel
        imageUrls = await Future.wait(uploadFutures);
      }

      // 2. Insert Post
      final response = await _client
          .from('posts')
          .insert({
            'user_id': userId,
            'content': content,
            'latitude': latitude,
            'longitude': longitude,
            'h3_cell': h3Cell,
            'image_urls': imageUrls,
            'image_url': imageUrls?.isNotEmpty == true
                ? imageUrls!.first
                : null,
            'gif_url': gifUrl,
          })
          .select('''
            *,
            user:user_id (
              id,
              display_name,
              avatar_url
            )
          ''')
          .single();

      // ✅ Publish to Ably philippines channel for real-time updates
      AblyService().publishPostCreated(
        city: 'philippines', // ✅ Changed from h3Cell
        postData: response,
      );

      return response;
    } catch (e) {
      print('❌ Error creating post: $e');
      return null;
    }
  }

  /// Create a system post (e.g., Hangout Card) without images but with metadata
  Future<Map<String, dynamic>?> createSystemPost({
    required String content,
    required String postType, // 'hangout', etc
    required Map<String, dynamic> metadata,
    String visibility = 'public', // public, followers, private
    double? latitude,
    double? longitude,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      // Calculate H3 cell
      String? h3Cell;
      if (latitude != null && longitude != null) {
        h3Cell = _calculateH3Cell(latitude, longitude);
      }

      final response = await _client
          .from('posts')
          .insert({
            'user_id': userId,
            'content': content,
            'latitude': latitude,
            'longitude': longitude,
            'h3_cell': h3Cell,
            'post_type': postType,
            'metadata': metadata,
            'visibility': visibility,
          })
          .select('''
            *,
            user:user_id (
              id,
              display_name,
              avatar_url
            )
          ''')
          .single();

      // ✅ Publish to Ably philippines channel (only public posts)
      if (visibility == 'public') {
        AblyService().publishPostCreated(
          city: 'philippines', // ✅ Changed from h3Cell
          postData: response,
        );
      }

      return response;
    } catch (e) {
      print('❌ Error creating system post: $e');
      return null;
    }
  }

  /// Toggle Like on a Post
  Future<bool> togglePostLike(String postId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      // Check if already liked
      final existing = await _client
          .from('post_likes')
          .select()
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Unlike
        await _client
            .from('post_likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', userId);
        return false;
      } else {
        // Like
        await _client.from('post_likes').insert({
          'post_id': postId,
          'user_id': userId,
        });

        // Notification now handled by database trigger (handle_new_like)

        return true;
      }
    } catch (e) {
      print('❌ Error toggling like: $e');
      return false;
    }
  }

  /// Toggle Bookmark on a Post
  Future<bool> toggleBookmark(String postId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      // Check if already bookmarked
      final existing = await _client
          .from('post_bookmarks')
          .select()
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Un-bookmark
        await _client
            .from('post_bookmarks')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', userId);
        return false;
      } else {
        // Bookmark
        await _client.from('post_bookmarks').insert({
          'post_id': postId,
          'user_id': userId,
        });
        return true;
      }
    } catch (e) {
      print('❌ Error toggling bookmark: $e');
      return false;
    }
  }

  /// Get Bookmarked Posts
  Future<List<Map<String, dynamic>>> getBookmarkedPosts() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('post_bookmarks')
          .select('''
            post:posts!inner(
              *,
              post_likes(count),
              comments(count)
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      // Transform to match Feed format
      // Note: This is a simpler fetch than the main feed, might lack user_datajoin if not careful
      // We need to fetch user data manually or via join if we want rich cards
      // For now, let's keep it simple or use a dedicated view/RPC if needed.
      // Actually, let's just do a manual fetch/transform loop to match `getFeed` output structure
      // or better, create an RPC for this too?
      // For simplicity, let's reuse get_philippines_feed logic or similar client-side join.

      // Better approach: Just use standard select with joins
      final data = await _client
          .from('post_bookmarks')
          .select('''
            created_at,
            post:posts!inner (
              *,
              user:users!user_id (
                id,
                display_name,
                avatar_url,
                username
              ),
              post_likes (user_id),
              comments (count)
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> posts = [];
      for (var item in data) {
        final post = item['post'] as Map<String, dynamic>;
        final likes = post['post_likes'] as List;

        posts.add({
          ...post,
          'user': post['user'], // mapped correctly
          'likes_count': likes.length,
          'is_liked': likes.any((l) => l['user_id'] == userId),
          'user_has_liked': likes.any((l) => l['user_id'] == userId),
          'user_has_bookmarked': true, // Obviously
          'comment_count': (post['comments'] as List).length,
        });
      }
      return posts;
    } catch (e) {
      print('❌ Error getting bookmarks: $e');
      return [];
    }
  }

  /// Get comments for a post
  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    try {
      final response = await _client
          .from('comments')
          .select('''
            *,
            user:user_id!inner (
              id,
              display_name,
              avatar_url,
              user_photos (photo_url, is_primary)
            ),
            comment_likes (user_id)
          ''')
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response).map((comment) {
        // Enrich user avatar logic (same as feed)
        final userData = comment['user'] as Map<String, dynamic>?;
        String? avatarUrl = userData?['avatar_url'];
        if (avatarUrl == null &&
            userData != null &&
            userData['user_photos'] != null) {
          final photos = userData['user_photos'] as List;
          if (photos.isNotEmpty) {
            final primary = photos.firstWhere(
              (p) => p['is_primary'] == true,
              orElse: () => photos.first,
            );
            avatarUrl = primary['photo_url'];
          }
        }

        final likes = comment['comment_likes'] as List;
        final currentUserId = _client.auth.currentUser?.id;

        return {
          ...comment,
          'user': {...userData ?? {}, 'avatar_url': avatarUrl},
          'like_count': likes.length,
          'is_liked': likes.any((l) => l['user_id'] == currentUserId),
          'replies': [], // Will be populated by UI or recursive logic if needed
        };
      }).toList();
    } catch (e) {
      print('❌ Error fetching comments: $e');
      return [];
    }
  }

  /// Add a comment (or reply)
  Future<Map<String, dynamic>?> addComment({
    required String postId,
    required String content,
    String? parentId,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _client
          .from('comments')
          .insert({
            'post_id': postId,
            'user_id': userId,
            'content': content,
            'parent_id': parentId,
          })
          .select('''
            *,
            user:user_id!inner (
              id,
              display_name,
              avatar_url,
              user_photos (photo_url, is_primary)
            )
          ''')
          .single();

      // Ensure user avatar is populated in return for immediate UI update
      final userData = response['user'] as Map<String, dynamic>?;
      String? avatarUrl = userData?['avatar_url'];
      if (avatarUrl == null &&
          userData != null &&
          userData['user_photos'] != null) {
        final photos = userData['user_photos'] as List;
        if (photos.isNotEmpty) {
          final primary = photos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => photos.first,
          );
          avatarUrl = primary['photo_url'];
        }
      }

      // NOTIFY POST AUTHOR (or parent comment author if reply)
      try {
        if (parentId != null) {
          // Reply to comment - notify the comment author
          final parentComment = await _client
              .from('comments')
              .select('user_id')
              .eq('id', parentId)
              .single();

          final commentAuthorId = parentComment['user_id'];

          if (commentAuthorId != userId) {
            // Notification now handled by database trigger (handle_new_comment)
            // await _client.from('notifications').insert({
            //   'user_id': commentAuthorId,
            //   'actor_id': userId,
            //   'type': 'comment',
            //   'title': 'New Reply',
            //   'body': 'Someone replied to your comment',
            //   'entity_id': postId,
            //   'metadata': {'post_id': postId, 'comment_id': response['id']},
            // });
          }
        } else {
          // Top-level comment - notify post author
          final post = await _client
              .from('posts')
              .select('user_id')
              .eq('id', postId)
              .single();

          final postAuthorId = post['user_id'];

          if (postAuthorId != userId) {
            // Notification now handled by database trigger (handle_new_comment)
          }
        }
      } catch (e) {
        print('⚠️ Failed to create comment notification: $e');
      }

      return {
        ...response,
        'user': {...userData ?? {}, 'avatar_url': avatarUrl},
        'like_count': 0,
        'is_liked': false,
        'replies': [],
      };
    } catch (e) {
      print('❌ Error adding comment: $e');
      return null;
    }
  }

  /// Toggle Like on a Comment
  Future<bool> toggleCommentLike(String commentId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      // Check if already liked
      final existing = await _client
          .from('comment_likes')
          .select()
          .eq('comment_id', commentId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', userId);
        return false;
      } else {
        await _client.from('comment_likes').insert({
          'comment_id': commentId,
          'user_id': userId,
        });
        return true;
      }
    } catch (e) {
      print('❌ Error toggling comment like: $e');
      return false;
    }
  }

  // -----------------------------------------------------------------------------
  // Follows
  // -----------------------------------------------------------------------------

  Future<void> followUser(String targetUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('follows').insert({
        'follower_id': user.id,
        'following_id': targetUserId,
      });
    } catch (e) {
      print('Error following user: $e');
      rethrow;
    }
  }

  Future<void> unfollowUser(String targetUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('follows').delete().match({
        'follower_id': user.id,
        'following_id': targetUserId,
      });
    } catch (e) {
      print('Error unfollowing user: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final response = await _client
          .from('follows')
          .select(
            'follower:users!follower_id(*, user_photos(photo_url, is_primary))',
          )
          .eq('following_id', userId);

      return List<Map<String, dynamic>>.from(
        response.map((e) {
          final user = e['follower'] as Map<String, dynamic>;
          // Enrich avatar_url if missing
          if (user['avatar_url'] == null && user['user_photos'] != null) {
            final photos = user['user_photos'] as List;
            if (photos.isNotEmpty) {
              final primary = photos.firstWhere(
                (p) => p['is_primary'] == true,
                orElse: () => photos.first,
              );
              user['avatar_url'] = primary['photo_url'];
            }
          }
          return user;
        }),
      );
    } catch (e) {
      print('Error getting followers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final response = await _client
          .from('follows')
          .select(
            'following:users!following_id(*, user_photos(photo_url, is_primary))',
          )
          .eq('follower_id', userId);

      return List<Map<String, dynamic>>.from(
        response.map((e) {
          final user = e['following'] as Map<String, dynamic>;
          // Enrich avatar_url if missing
          if (user['avatar_url'] == null && user['user_photos'] != null) {
            final photos = user['user_photos'] as List;
            if (photos.isNotEmpty) {
              final primary = photos.firstWhere(
                (p) => p['is_primary'] == true,
                orElse: () => photos.first,
              );
              user['avatar_url'] = primary['photo_url'];
            }
          }
          return user;
        }),
      );
    } catch (e) {
      print('Error getting following: $e');
      return [];
    }
  }

  Future<bool> isFollowing(String targetUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _client.from('follows').select().match({
        'follower_id': user.id,
        'following_id': targetUserId,
      }).maybeSingle();

      return response != null;
    } catch (e) {
      print('Error checking isFollowing: $e');
      return false;
    }
  }

  // -----------------------------------------------------------------------------
  // Edit & Delete Operations
  // -----------------------------------------------------------------------------

  /// Edit a post (only content and gif_url; images are immutable after creation)
  Future<Map<String, dynamic>?> editPost({
    required String postId,
    required String content,
    String? gifUrl,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final updateData = <String, dynamic>{'content': content};

      // Allow clearing or changing gif
      if (gifUrl != null) {
        updateData['gif_url'] = gifUrl;
      }

      final response = await _client
          .from('posts')
          .update(updateData)
          .match({'id': postId, 'user_id': userId})
          .select('''
            *,
            user:user_id (
              id,
              display_name,
              avatar_url
            )
          ''')
          .single();

      return response;
    } catch (e) {
      print('❌ Error editing post: $e');
      return null;
    }
  }

  /// Delete a post (only if user is the owner)
  Future<bool> deletePost(String postId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      // Delete the post
      await _client.from('posts').delete().match({
        'id': postId,
        'user_id': userId,
      });

      // ✅ Publish deletion to Ably philippines channel
      AblyService().publishPostDeleted(
        city: 'philippines', // ✅ Changed from h3Cell
        postId: postId,
      );

      return true;
    } catch (e) {
      print('❌ Error deleting post: $e');
      return false;
    }
  }

  /// Delete a comment (only if user is the owner)
  Future<bool> deleteComment(String commentId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      await _client.from('comments').delete().match({
        'id': commentId,
        'user_id': userId,
      });

      return true;
    } catch (e) {
      print('❌ Error deleting comment: $e');
      return false;
    }
  }

  // -----------------------------------------------------------------------------
  // H3 Geospatial Helper Methods
  // -----------------------------------------------------------------------------

  /// Calculate H3 cell at resolution 7 from coordinates
  String? _calculateH3Cell(double latitude, double longitude) {
    try {
      final h3 = const H3Factory().load();
      final cell = h3.geoToCell(GeoCoord(lat: latitude, lon: longitude), 7);
      return cell.toString();
    } catch (e) {
      if (e.toString().contains('symbol not found')) {
        print(
          '❌ H3 Native Error: Library not linked. Please run "flutter clean" and "pod install" in macos/ios folder.',
        );
      } else {
        print('❌ Error calculating H3 cell: $e');
      }
      return null;
    }
  }

  /// Get H3 cells for location (center + k-ring of 2 for ~40km coverage)
  List<String> getH3CellsForLocation(double latitude, double longitude) {
    try {
      final h3 = const H3Factory().load();
      final centerCell = h3.geoToCell(
        GeoCoord(lat: latitude, lon: longitude),
        7,
      );
      // Get grid disk of radius 2 (includes center + 2 rings of neighbors)
      final cells = h3.gridDisk(centerCell, 2);

      return cells.map((cell) => cell.toString()).toList();
    } catch (e) {
      if (e.toString().contains('symbol not found')) {
        print(
          '❌ H3 Native Error: Library not linked. Please run "flutter clean" and "pod install" in macos/ios folder.',
        );
      } else {
        print('❌ Error getting H3 cells: $e');
      }
      return [];
    }
  }
}
