import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupService {
  // ═══════════════════════════════════════════════
  // CREATE
  // ═══════════════════════════════════════════════

  /// Create a new group. Creator is automatically added as owner.
  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? description,
    String? rules,
    String category = 'other',
    String privacy = 'public',
    String? iconEmoji,
    String? locationCity,
    double? locationLat,
    double? locationLng,
    File? coverImage,
  }) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // 1. Insert the group
      final response = await SupabaseConfig.client
          .from('groups')
          .insert({
            'name': name,
            'description': description,
            'rules': rules,
            'category': category,
            'privacy': privacy,
            'icon_emoji': iconEmoji,
            'location_city': locationCity,
            'location_lat': locationLat,
            'location_lng': locationLng,
            'created_by': user.id,
            'member_count': 1,
          })
          .select('id')
          .single();

      final groupId = response['id'] as String;

      // 2. Upload cover image if provided
      if (coverImage != null) {
        final coverUrl = await _uploadCoverImage(groupId, coverImage);
        if (coverUrl != null) {
          await SupabaseConfig.client
              .from('groups')
              .update({'cover_image_url': coverUrl})
              .eq('id', groupId);
        }
      }

      // 3. Add creator as owner (auto-approved)
      await SupabaseConfig.client.from('group_members').insert({
        'group_id': groupId,
        'user_id': user.id,
        'role': 'owner',
        'status': 'approved',
        'joined_at': DateTime.now().toUtc().toIso8601String(),
        'last_read_at': DateTime.now().toUtc().toIso8601String(),
      });

      return {'success': true, 'group_id': groupId};
    } catch (e) {
      print('❌ GROUP SERVICE: Error creating group - $e');
      return {'success': false, 'message': 'Failed to create group: $e'};
    }
  }

  // ═══════════════════════════════════════════════
  // READ
  // ═══════════════════════════════════════════════

  /// Get a single group by ID with creator info
  Future<Map<String, dynamic>?> getGroup(String groupId) async {
    try {
      final group = await SupabaseConfig.client
          .from('groups')
          .select('''
            *,
            creator:created_by (
              id,
              display_name,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('id', groupId)
          .single();

      return Map<String, dynamic>.from(group);
    } catch (e) {
      print('❌ GROUP SERVICE: Error fetching group - $e');
      return null;
    }
  }

  /// Get groups the current user belongs to
  Future<List<Map<String, dynamic>>> getMyGroups() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return [];

      final memberships = await SupabaseConfig.client
          .from('group_members')
          .select('''
            group_id,
            role,
            status,
            joined_at,
            groups:group_id (
              id,
              name,
              description,
              category,
              privacy,
              icon_emoji,
              cover_image_url,
              member_count,
              created_at
            )
          ''')
          .eq('user_id', user.id)
          .eq('status', 'approved')
          .order('joined_at', ascending: false);

      return List<Map<String, dynamic>>.from(memberships);
    } catch (e) {
      print('❌ GROUP SERVICE: Error fetching my groups - $e');
      return [];
    }
  }

  /// Discover groups — browse/search public groups
  Future<List<Map<String, dynamic>>> discoverGroups({
    String? category,
    String? city,
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      var dbQuery = SupabaseConfig.client
          .from('groups')
          .select('*')
          .inFilter('privacy', ['public', 'private']);

      if (category != null && category != 'all') {
        dbQuery = dbQuery.eq('category', category);
      }

      if (city != null) {
        dbQuery = dbQuery.eq('location_city', city);
      }

      if (query != null && query.isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%$query%');
      }

      final response = await dbQuery
          .order('member_count', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ GROUP SERVICE: Error discovering groups - $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════
  // UPDATE
  // ═══════════════════════════════════════════════

  /// Update group details (admin/owner only — enforced by RLS)
  Future<Map<String, dynamic>> updateGroup(
    String groupId, {
    String? name,
    String? description,
    String? rules,
    String? category,
    String? privacy,
    String? iconEmoji,
    String? locationCity,
    File? coverImage,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (rules != null) updates['rules'] = rules;
      if (category != null) updates['category'] = category;
      if (privacy != null) updates['privacy'] = privacy;
      if (iconEmoji != null) updates['icon_emoji'] = iconEmoji;
      if (locationCity != null) updates['location_city'] = locationCity;

      // Upload new cover image
      if (coverImage != null) {
        final coverUrl = await _uploadCoverImage(groupId, coverImage);
        if (coverUrl != null) updates['cover_image_url'] = coverUrl;
      }

      await SupabaseConfig.client
          .from('groups')
          .update(updates)
          .eq('id', groupId);

      return {'success': true};
    } catch (e) {
      print('❌ GROUP SERVICE: Error updating group - $e');
      return {'success': false, 'message': 'Failed to update group: $e'};
    }
  }

  // ═══════════════════════════════════════════════
  // DELETE
  // ═══════════════════════════════════════════════

  /// Delete a group (owner only — enforced by RLS)
  Future<Map<String, dynamic>> deleteGroup(String groupId) async {
    try {
      await SupabaseConfig.client
          .from('groups')
          .delete()
          .eq('id', groupId);

      return {'success': true};
    } catch (e) {
      print('❌ GROUP SERVICE: Error deleting group - $e');
      return {'success': false, 'message': 'Failed to delete group: $e'};
    }
  }

  // ═══════════════════════════════════════════════
  // GROUP FEED
  // ═══════════════════════════════════════════════

  /// Get posts scoped to a group
  Future<List<Map<String, dynamic>>> getGroupFeed(
    String groupId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            users:user_id (
              id,
              display_name,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ GROUP SERVICE: Error fetching group feed - $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════
  // GROUP ACTIVITIES
  // ═══════════════════════════════════════════════

  /// Get activities (tables) created by this group
  Future<List<Map<String, dynamic>>> getGroupActivities(
    String groupId, {
    bool upcomingOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      var query = SupabaseConfig.client
          .from('tables')
          .select('''
            id, title, description, datetime, location_name, venue_address,
            latitude, longitude, max_guests, status, visibility,
            marker_emoji, marker_image_url, image_url,
            host_id,
            host:host_id (
              id,
              display_name,
              user_photos (
                photo_url,
                is_primary
              )
            )
          ''')
          .eq('group_id', groupId);

      if (upcomingOnly) {
        query = query.gte('datetime', DateTime.now().toUtc().toIso8601String());
      }

      final response = await query
          .order('datetime', ascending: true)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ GROUP SERVICE: Error fetching group activities - $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════

  Future<String?> _uploadCoverImage(String groupId, File imageFile) async {
    try {
      final fileExt = imageFile.path.split('.').last;
      final fileName = '$groupId.$fileExt';
      final bytes = await imageFile.readAsBytes();

      await SupabaseConfig.client.storage
          .from('group-covers')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = SupabaseConfig.client.storage
          .from('group-covers')
          .getPublicUrl(fileName);

      // Append cache-buster so updated images show immediately
      return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('❌ GROUP SERVICE: Error uploading cover - $e');
      return null;
    }
  }
}
