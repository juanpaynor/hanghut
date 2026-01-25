import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/widgets/avatar_stack.dart';
import 'package:bitemates/features/shared/widgets/report_modal.dart';

class TableCompactModal extends StatefulWidget {
  final Map<String, dynamic> table;
  final Map<String, dynamic>? matchData;

  const TableCompactModal({super.key, required this.table, this.matchData});

  @override
  State<TableCompactModal> createState() => _TableCompactModalState();
}

class _TableCompactModalState extends State<TableCompactModal> {
  final _memberService = TableMemberService();
  bool _isLoading = false;
  Map<String, dynamic>? _membershipStatus;
  bool _isHost = false;
  List<String> _memberPhotoUrls = [];
  int _totalMembers = 0;

  void initState() {
    super.initState();
    print('🎬 TABLE MODAL DEBUG:');
    print('  - Table ID: ${widget.table['id']}');
    print('  - image_url: ${widget.table['image_url']}');
    print('  - marker_image_url: ${widget.table['marker_image_url']}');
    _checkMembershipStatus();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      final members = await _memberService.getTableMembers(widget.table['id']);
      final photos = <String>[];

      for (var member in members) {
        final user = member['users'];
        if (user == null) continue;

        String? photoUrl = user['avatar_url'];

        // Try to find primary photo from user_photos if available
        if (user['user_photos'] != null) {
          final userPhotos = List<Map<String, dynamic>>.from(
            user['user_photos'],
          );
          final primary = userPhotos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => userPhotos.isNotEmpty ? userPhotos.first : {},
          );
          if (primary.isNotEmpty && primary['photo_url'] != null) {
            photoUrl = primary['photo_url'];
          }
        }

        if (photoUrl != null) {
          photos.add(photoUrl);
        }
      }

      if (mounted) {
        setState(() {
          _memberPhotoUrls = photos;
          _totalMembers = members.length;
        });
      }
    } catch (e) {
      print('❌ Error fetching members for bubbles: $e');
    }
  }

  Future<void> _checkMembershipStatus() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    _isHost = widget.table['host_id'] == user.id;

    if (!_isHost) {
      final status = await _memberService.getUserMembershipStatus(
        widget.table['id'],
      );
      if (mounted) {
        setState(() {
          _membershipStatus = status;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Use 'datetime' column and handle nulls
    final scheduledAt = DateTime.parse(
      widget.table['datetime'] ??
          widget.table['scheduled_time'] ??
          DateTime.now().toIso8601String(),
    );
    final currentCapacity = widget.table['current_capacity'] ?? 0;
    final maxCapacity =
        widget.table['max_guests'] ?? widget.table['max_capacity'] ?? 0;

    // Data Fallbacks
    final displayTitle =
        widget.table['title'] ??
        widget.table['venue_name'] ??
        widget.table['location_name'] ??
        'Unknown Activity';

    final displayVenue =
        widget.table['location_name'] ?? widget.table['venue_name'];

    final matchScore = widget.matchData != null
        ? (widget.matchData!['score'] * 100).toInt()
        : 0;

    final matchColor = widget.matchData != null
        ? Color(
            int.parse(
              (widget.matchData?['color'] ?? '#666666').replaceFirst(
                '#',
                '0xFF',
              ),
            ),
          )
        : Colors.grey;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // Light background
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Image / Gradient Area
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: widget.table['image_url'] != null
                        ? CachedNetworkImage(
                            imageUrl: widget.table['image_url'],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black26,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.black26,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  matchColor,
                                  matchColor.withOpacity(0.6),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.restaurant_menu,
                                color: Colors.white54,
                                size: 56,
                              ),
                            ),
                          ),
                  ),

                  // Gradient Overlay for text readability (lighter for light theme or keep dark for contrast on image?)
                  // Keeping slight dark overlay only at top for close button visibility if image is light
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4],
                        ),
                      ),
                    ),
                  ),

                  // Report Button (Top Left)
                  if (!_isHost)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ReportModal(
                                entityType: 'table',
                                entityId: widget.table['id'],
                              ),
                            );
                          },
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.flag_outlined,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Close Button (Top Right)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.close,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Match Badge (Moved down slightly to avoid potential overlap with report)
                  if (matchScore > 0)
                    Positioned(
                      top: 56, // Moved down below buttons
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: matchColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$matchScore% Match',
                              style: TextStyle(
                                color: matchColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2. Info Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      color: Colors.black87, // Dark text
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (displayVenue != null && displayVenue != displayTitle) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            displayVenue,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Date Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100], // Light grey bg
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat(
                          'EEEE, MMM d  •  h:mm a',
                        ).format(scheduledAt),
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Host Row
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        // Host Avatar
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(
                                  userId: widget.table['host_id'],
                                ),
                              ),
                            );
                          },
                          child: CircleAvatar(
                            radius: 20,
                            backgroundImage:
                                widget.table['host_photo_url'] != null
                                ? NetworkImage(widget.table['host_photo_url'])
                                : null,
                            backgroundColor: Colors.grey[300],
                            child: widget.table['host_photo_url'] == null
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Host Name & Stats
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.table['host_name'] ?? 'Unknown Host',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (_memberPhotoUrls.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: AvatarStack(
                                        avatarUrls: _memberPhotoUrls,
                                        totalCount: _totalMembers,
                                        size: 24,
                                        borderColor: Colors.white,
                                        borderWidth: 1.5,
                                      ),
                                    ),
                                  Text(
                                    '$currentCapacity/$maxCapacity guests',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Actions
                  SizedBox(
                    height: 52, // Fixed height for button
                    child: _buildActionButtons(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
        ),
      );
    }

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.black, // Dark button for light theme
      foregroundColor: Colors.white,
      elevation: 0,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );

    final secondaryButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.grey[200], // Light grey secondary
      foregroundColor: Colors.black87,
      elevation: 0,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    if (_isHost) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: const Text('Open Chat'),
              style: buttonStyle,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: ElevatedButton(
              onPressed: _deleteTable,
              style: secondaryButtonStyle.copyWith(
                foregroundColor: MaterialStateProperty.all(Colors.red),
              ),
              child: const Icon(Icons.delete_outline, size: 22),
            ),
          ),
        ],
      );
    }

    if (_membershipStatus != null) {
      final status = _membershipStatus!['status'];
      if (status == 'approved' || status == 'joined') {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: const Text('Chat'),
                style: buttonStyle,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52,
              child: ElevatedButton(
                onPressed: _leaveTable,
                style: secondaryButtonStyle.copyWith(
                  foregroundColor: MaterialStateProperty.all(Colors.red),
                ),
                child: const Icon(Icons.logout, size: 22),
              ),
            ),
          ],
        );
      } else if (status == 'pending') {
        return ElevatedButton(
          onPressed: _cancelRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[50], // Very light orange
            foregroundColor: Colors.orange[800],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: const Text('Request Pending'),
        );
      }
    }

    // Join Button (Default)
    return ElevatedButton(
      onPressed: _joinTable,
      style: buttonStyle,
      child: const Text(
        'Join',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  // --- Logic copied and adapted from TableDetailsBottomSheet ---

  void _openChat() {
    Navigator.pop(context); // Close modal first

    // Data Fallbacks (same as build method)
    final venueName =
        widget.table['venue_name'] ??
        widget.table['title'] ??
        widget.table['location_name'] ??
        'Unknown Venue';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => ChatScreen(
        channelId: 'table_${widget.table['id']}',
        tableId: widget.table['id'],
        tableTitle: venueName,
      ),
    );
  }

  Future<void> _joinTable() async {
    setState(() => _isLoading = true);
    final result = await _memberService.joinTable(widget.table['id']);

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success']) {
        Navigator.pop(context, true); // Return true to refresh
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTable() async {
    // Show confirmation dialog before deleting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    await SupabaseConfig.client
        .from('tables')
        .delete()
        .eq('id', widget.table['id']);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _leaveTable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Table?'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    await _memberService.leaveTable(widget.table['id']);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _isLoading = true);
    await _memberService.leaveTable(widget.table['id']);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}
