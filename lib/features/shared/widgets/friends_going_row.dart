import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/friends_going_service.dart';

/// Reusable widget that shows which friends have joined an entity.
///
/// Displays stacked avatars and names:
/// "👤👤👤 John, Maria and 3 other friends are going"
///
/// Usage:
/// ```dart
/// FriendsGoingRow(entityType: 'event', entityId: event.id)
/// FriendsGoingRow(entityType: 'table', entityId: table['id'])
/// FriendsGoingRow(entityType: 'experience', entityId: experience['id'])
/// ```
class FriendsGoingRow extends StatefulWidget {
  final String entityType; // 'event', 'table', 'experience'
  final String entityId;

  const FriendsGoingRow({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  State<FriendsGoingRow> createState() => _FriendsGoingRowState();
}

class _FriendsGoingRowState extends State<FriendsGoingRow> {
  final _service = FriendsGoingService();
  List<Map<String, dynamic>> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    List<Map<String, dynamic>> result;

    switch (widget.entityType) {
      case 'event':
        result = await _service.getFriendsGoingToEvent(widget.entityId);
        break;
      case 'table':
        result = await _service.getFriendsAtTable(widget.entityId);
        break;
      case 'experience':
        result = await _service.getFriendsInExperience(widget.entityId);
        break;
      default:
        result = [];
    }

    if (mounted) {
      setState(() {
        _friends = result;
        _isLoading = false;
      });
    }
  }

  String get _verb {
    switch (widget.entityType) {
      case 'event':
        return 'going';
      case 'table':
        return 'joined';
      case 'experience':
        return 'booked';
      default:
        return 'going';
    }
  }

  void _showFullList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FriendsListSheet(friends: _friends, verb: _verb),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hide while loading or if no friends found
    if (_isLoading || _friends.isEmpty) return const SizedBox.shrink();

    const int maxAvatars = 3;
    final displayFriends = _friends.take(maxAvatars).toList();
    final overflowCount = _friends.length - maxAvatars;

    // Build the text label
    String label;
    if (_friends.length == 1) {
      label = '${_friends[0]['display_name']} is $_verb';
    } else if (_friends.length == 2) {
      label =
          '${_friends[0]['display_name']} and ${_friends[1]['display_name']} are $_verb';
    } else {
      label =
          '${_friends[0]['display_name']} and ${_friends.length - 1} other friends are $_verb';
    }

    return GestureDetector(
      onTap: _showFullList,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Stacked avatars
            SizedBox(
              width: 20.0 + (displayFriends.length * 22.0),
              height: 32,
              child: Stack(
                children: [
                  for (int i = 0; i < displayFriends.length; i++)
                    Positioned(
                      left: i * 22.0,
                      child: _FriendAvatar(
                        avatarUrl: displayFriends[i]['avatar_url'] as String?,
                        size: 32,
                      ),
                    ),
                  if (overflowCount > 0)
                    Positioned(
                      left: displayFriends.length * 22.0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '+$overflowCount',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Label text
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Individual avatar ───
class _FriendAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const _FriendAvatar({this.avatarUrl, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        color: Colors.grey[200],
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Icon(
                Icons.person,
                size: size * 0.5,
                color: Colors.grey[400],
              ),
              errorWidget: (_, __, ___) => Icon(
                Icons.person,
                size: size * 0.5,
                color: Colors.grey[400],
              ),
            )
          : Icon(
              Icons.person,
              size: size * 0.5,
              color: Colors.grey[400],
            ),
    );
  }
}

// ─── Bottom sheet showing full friends list ───
class _FriendsListSheet extends StatelessWidget {
  final List<Map<String, dynamic>> friends;
  final String verb;

  const _FriendsListSheet({required this.friends, required this.verb});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Friends who $verb',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        ...friends.map((friend) => ListTile(
              leading: _FriendAvatar(
                avatarUrl: friend['avatar_url'] as String?,
                size: 40,
              ),
              title: Text(
                friend['display_name'] ?? 'Unknown',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            )),
        const SizedBox(height: 20),
      ],
    );
  }
}
