import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/core/services/tenor_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/widgets/avatar_stack.dart';
import 'package:bitemates/features/shared/widgets/report_modal.dart';
import 'package:bitemates/features/map/widgets/pending_requests_sheet.dart';
import 'package:bitemates/features/map/widgets/manage_members_sheet.dart';
import 'package:bitemates/features/shared/widgets/friends_going_row.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';

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
  bool _isInvited = false;
  List<String> _memberPhotoUrls = [];
  int _totalMembers = 0;
  int _pendingCount = 0;
  String? _autoGifUrl;
  String? _hostName;
  String? _hostPhotoUrl;
  // Group-hosted
  String? _groupId;
  String? _groupCoverUrl;
  // Live table status (fetched from DB to guard against stale data)
  String? _liveTableStatus;
  bool _tableExists = true;

  @override
  void initState() {
    super.initState();
    _checkMembershipStatus();
    _fetchMembers();
    _fetchPendingCount();
    _fetchHostInfo();
    _fetchAutoGifIfNeeded();
    _fetchLiveTableStatus();
  }

  // ═══════════════════════════════════════════════
  // DATA FETCHING
  // ═══════════════════════════════════════════════

  /// Fetch the live status of the table from the database.
  /// The table data passed in may be stale (e.g., from a feed post snapshot).
  Future<void> _fetchLiveTableStatus() async {
    try {
      final result = await SupabaseConfig.client
          .from('tables')
          .select('status')
          .eq('id', widget.table['id'])
          .maybeSingle();

      if (mounted) {
        if (result == null) {
          setState(() => _tableExists = false);
        } else {
          setState(() => _liveTableStatus = result['status']);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching live table status: $e');
    }
  }

  Future<void> _fetchAutoGifIfNeeded() async {
    if (widget.table['image_url'] != null ||
        widget.table['marker_image_url'] != null)
      return;

    try {
      final title = widget.table['title']?.toString() ?? '';
      String searchQuery = title;
      final wantsToIndex = title.toLowerCase().indexOf('wants to ');
      if (wantsToIndex != -1) {
        searchQuery = title.substring(wantsToIndex + 9);
      }

      if (searchQuery.isEmpty) return;

      final lowerQuery = searchQuery.toLowerCase();
      const activityKeywords = {
        'coffee': 'coffee cafe latte',
        'tea': 'tea drinking',
        'eat': 'eating food delicious',
        'food': 'food eating yummy',
        'drink': 'drink cheers bar',
        'beer': 'beer cheers pub',
        'wine': 'wine cheers dinner',
        'cocktail': 'cocktail bar drinks',
        'mead': 'drink cheers medieval',
        'brunch': 'brunch food morning',
        'lunch': 'lunch food eating',
        'dinner': 'dinner food restaurant',
        'pizza': 'pizza delicious food',
        'sushi': 'sushi japanese food',
        'ramen': 'ramen noodles food',
        'bbq': 'barbecue grilling food',
        'gym': 'gym workout fitness',
        'run': 'running jogging fitness',
        'yoga': 'yoga exercise stretch',
        'swim': 'swimming pool',
        'basketball': 'basketball dunk nba',
        'soccer': 'soccer football goal',
        'tennis': 'tennis match',
        'golf': 'golf swing',
        'hike': 'hiking mountain nature',
        'bike': 'cycling bike ride',
        'dance': 'dancing party moves',
        'karaoke': 'karaoke singing',
        'movie': 'movie cinema popcorn',
        'game': 'gaming video games',
        'party': 'party celebration fun',
        'concert': 'concert live music',
        'study': 'studying books focus',
        'cook': 'cooking chef kitchen',
        'paint': 'painting art creative',
        'shop': 'shopping mall retail',
        'chill': 'chill relax vibes',
        'hangout': 'hangout friends chill',
        'beach': 'beach summer vibes',
        'travel': 'travel adventure explore',
        'camp': 'camping outdoor nature',
        'climb': 'rock climbing',
        'skate': 'skateboarding tricks',
        'bowl': 'bowling strike',
      };

      for (final entry in activityKeywords.entries) {
        if (lowerQuery.contains(entry.key)) {
          searchQuery = entry.value;
          break;
        }
      }

      final tenor = TenorService();
      final results = await tenor.searchGifs(searchQuery, limit: 5);

      if (results.isNotEmpty && mounted) {
        final randomIndex =
            DateTime.now().millisecondsSinceEpoch % results.length;
        final gifUrl = tenor.getGifUrl(results[randomIndex]);
        if (gifUrl.isNotEmpty) {
          setState(() => _autoGifUrl = gifUrl);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Auto-GIF fetch failed: $e');
    }
  }

  Future<void> _fetchHostInfo() async {
    // Check if this is a group-hosted activity
    final groupId = widget.table['group_id'] as String?;
    if (groupId != null) {
      try {
        final groupResult = await SupabaseConfig.client
            .from('groups')
            .select('id, name, cover_image_url')
            .eq('id', groupId)
            .maybeSingle();

        if (groupResult != null && mounted) {
          setState(() {
            _groupId = groupId;
            _groupCoverUrl = groupResult['cover_image_url'];
            _hostName = groupResult['name'];
            _hostPhotoUrl = groupResult['cover_image_url'];
          });
        }
      } catch (e) {
        debugPrint('❌ Error fetching group host info: $e');
      }
      return;
    }

    // Personal host
    final hostId = widget.table['host_id'];
    if (hostId == null) return;

    try {
      final result = await SupabaseConfig.client
          .from('users')
          .select('display_name, user_photos(photo_url, is_primary)')
          .eq('id', hostId)
          .maybeSingle();

      if (result != null && mounted) {
        String? photoUrl;
        if (result['user_photos'] != null) {
          final photos = List<Map<String, dynamic>>.from(result['user_photos']);
          final primary = photos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => photos.isNotEmpty ? photos.first : {},
          );
          if (primary.isNotEmpty) photoUrl = primary['photo_url'];
        }

        setState(() {
          _hostName = result['display_name'];
          _hostPhotoUrl = photoUrl;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching host info: $e');
    }
  }

  Future<void> _fetchPendingCount() async {
    try {
      final requests = await _memberService.getPendingRequests(
        widget.table['id'],
      );
      if (mounted) {
        setState(() => _pendingCount = requests.length);
      }
    } catch (_) {}
  }

  Future<void> _fetchMembers() async {
    try {
      final members = await _memberService.getTableMembers(widget.table['id']);
      final photos = <String>[];

      for (var member in members) {
        final user = member['users'];
        if (user == null) continue;

        String? photoUrl = user['avatar_url'];

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
      debugPrint('❌ Error fetching members for bubbles: $e');
    }
  }

  Future<void> _checkMembershipStatus() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    _isHost = widget.table['host_id'] == user.id;

    final invitedIds = widget.table['invited_user_ids'];
    if (invitedIds is List && invitedIds.contains(user.id)) {
      _isInvited = true;
    }

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

  // ═══════════════════════════════════════════════
  // BUILD — REDESIGNED UI
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    // Surface colors from theme
    final modalBg = isDark ? AppTheme.darkSurface : Colors.white;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary;
    final subtextColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.textSecondary;
    final pillBg = isDark
        ? AppTheme.darkSurfaceVariant
        : const Color(0xFFF0F0F5);
    final pillTextColor = isDark ? Colors.white : primaryColor;

    // Data
    final scheduledAt = DateTime.parse(
      widget.table['datetime'] ??
          widget.table['scheduled_time'] ??
          DateTime.now().toIso8601String(),
    );
    final currentCapacity = widget.table['current_capacity'] ?? 0;
    final maxCapacity =
        widget.table['max_guests'] ?? widget.table['max_capacity'] ?? 0;

    final displayTitle =
        widget.table['title'] ??
        widget.table['venue_name'] ??
        widget.table['location_name'] ??
        'Unknown Activity';

    final displayVenue =
        widget.table['location_name'] ?? widget.table['venue_name'];

    final matchScore =
        (widget.matchData != null && widget.matchData!['score'] != null)
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

    // Resolve hero image
    final String? heroImageUrl =
        widget.table['image_url'] ??
        widget.table['marker_image_url'] ??
        _autoGifUrl;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Content ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ═══════════════════════════════════════
                  // 1. EDGE-TO-EDGE HERO IMAGE
                  // ═══════════════════════════════════════
                  SizedBox(
                    height: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image — edge to edge, clipped by modal's top radius
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          child: heroImageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: heroImageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: isDark
                                        ? Colors.grey[800]
                                        : Colors.grey[200],
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: primaryColor.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      _buildFallbackHero(matchColor, isDark),
                                )
                              : _buildFallbackHero(matchColor, isDark),
                        ),

                        // Gradient overlay at bottom for text legibility
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 80,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [modalBg, modalBg.withOpacity(0.0)],
                              ),
                            ),
                          ),
                        ),

                        // Drag Handle (overlaid on image)
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),

                        // Match Badge (bottom-left)
                        if (matchScore > 0)
                          Positioned(
                            bottom: 12,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black.withOpacity(0.7)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    color: matchColor,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$matchScore% Match',
                                    style: GoogleFonts.inter(
                                      color: matchColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Report Button (Top Left)
                        if (!_isHost)
                          Positioned(
                            top: 8,
                            left: 12,
                            child: _buildOverlayButton(
                              icon: Icons.flag_outlined,
                              isDark: isDark,
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
                            ),
                          ),

                        // Close Button (Top Right)
                        Positioned(
                          top: 8,
                          right: 12,
                          child: _buildOverlayButton(
                            icon: Icons.close,
                            isDark: isDark,
                            onTap: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ═══════════════════════════════════════
                  // 2. CONTENT
                  // ═══════════════════════════════════════
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Title ──
                        Text(
                          displayTitle,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 12),

                        // ── Pill Tags (Date & Location) ──
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildPill(
                              icon: Icons.calendar_today_rounded,
                              label: DateFormat(
                                'EEE, MMM d • h:mm a',
                              ).format(scheduledAt),
                              bg: pillBg,
                              fg: pillTextColor,
                              iconColor: primaryColor,
                            ),
                            if (displayVenue != null &&
                                displayVenue != displayTitle)
                              _buildPill(
                                icon: Icons.location_on_rounded,
                                label: displayVenue,
                                bg: pillBg,
                                fg: pillTextColor,
                                iconColor: primaryColor,
                              ),
                            _buildPill(
                              icon: Icons.people_rounded,
                              label: '$currentCapacity / $maxCapacity spots',
                              bg: pillBg,
                              fg: pillTextColor,
                              iconColor: primaryColor,
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // ── Host Row (borderless) ──
                        GestureDetector(
                          onTap: () {
                            if (_groupId != null) {
                              // Navigate to group detail
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      GroupDetailScreen(groupId: _groupId!),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(
                                    userId: widget.table['host_id'],
                                  ),
                                ),
                              );
                            }
                          },
                          child: Row(
                            children: [
                              // Host/Group Avatar
                              Container(
                                decoration: BoxDecoration(
                                  shape: _groupId != null
                                      ? BoxShape.rectangle
                                      : BoxShape.circle,
                                  borderRadius: _groupId != null
                                      ? BorderRadius.circular(10)
                                      : null,
                                  border: Border.all(
                                    color: primaryColor.withOpacity(0.4),
                                    width: 2,
                                  ),
                                ),
                                child: _groupId != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: (_groupCoverUrl != null)
                                            ? Image.network(
                                                _groupCoverUrl!,
                                                width: 56,
                                                height: 56,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 56,
                                                height: 56,
                                                color: isDark
                                                    ? Colors.grey[800]
                                                    : Colors.grey[200],
                                                child: Icon(
                                                  Icons.groups,
                                                  color: subtextColor,
                                                  size: 24,
                                                ),
                                              ),
                                      )
                                    : CircleAvatar(
                                        radius: 28,
                                        backgroundImage:
                                            (_hostPhotoUrl ??
                                                    widget
                                                        .table['host_photo_url']) !=
                                                null
                                            ? NetworkImage(
                                                _hostPhotoUrl ??
                                                    widget
                                                        .table['host_photo_url'],
                                              )
                                            : null,
                                        backgroundColor: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[200],
                                        child:
                                            (_hostPhotoUrl ??
                                                    widget
                                                        .table['host_photo_url']) ==
                                                null
                                            ? Icon(
                                                Icons.person,
                                                color: subtextColor,
                                                size: 24,
                                              )
                                            : null,
                                      ),
                              ),
                              const SizedBox(width: 12),

                              // Host/Group Name & Label
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _groupId != null
                                        ? 'Hosted by group'
                                        : 'Hosted by',
                                    style: GoogleFonts.inter(
                                      color: subtextColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    _hostName ??
                                        widget.table['host_name'] ??
                                        'Loading...',
                                    style: GoogleFonts.inter(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(width: 12),

                              // Attendee Avatar Stack
                              if (_memberPhotoUrls.isNotEmpty)
                                AvatarStack(
                                  avatarUrls: _memberPhotoUrls,
                                  totalCount: _totalMembers,
                                  size: 36,
                                  borderColor: modalBg,
                                  borderWidth: 2,
                                ),
                            ],
                          ),
                        ),

                        // ── Friends Going ──
                        FriendsGoingRow(
                          entityType: 'table',
                          entityId: widget.table['id'],
                        ),

                        // ── Description ──
                        if (widget.table['description'] != null &&
                            widget.table['description']
                                .toString()
                                .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.table['description'],
                            style: GoogleFonts.inter(
                              color: subtextColor,
                              fontSize: 13,
                              height: 1.5,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),

              // ═══════════════════════════════════════
              // 3. PINNED ACTION BUTTONS
              // ═══════════════════════════════════════
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  color: modalBg,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 0.5,
                    ),
                  ),
                ),
                child: SizedBox(
                  height: 50,
                  child: _buildActionButtons(theme, isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════

  Widget _buildFallbackHero(Color matchColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            matchColor.withOpacity(isDark ? 0.4 : 0.8),
            matchColor.withOpacity(isDark ? 0.2 : 0.4),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          color: Colors.white.withOpacity(0.5),
          size: 56,
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark
          ? Colors.black.withOpacity(0.5)
          : Colors.white.withOpacity(0.9),
      elevation: 0,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            icon,
            color: isDark ? Colors.white70 : Colors.black87,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // ACTION BUTTONS (theme-aware)
  // ═══════════════════════════════════════════════

  Widget _buildActionButtons(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final primaryColor = theme.colorScheme.primary;

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 6,
      shadowColor: primaryColor.withOpacity(0.4),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );

    final secondaryButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: isDark ? AppTheme.darkSurfaceVariant : Colors.grey[100],
      foregroundColor: isDark ? Colors.white70 : Colors.black87,
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
          const SizedBox(width: 8),
          // Pending Requests Button with badge
          SizedBox(
            width: 52,
            child: Stack(
              children: [
                ElevatedButton(
                  onPressed: _openPendingRequests,
                  style: secondaryButtonStyle,
                  child: const Icon(Icons.person_add, size: 22),
                ),
                if (_pendingCount > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        '$_pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Manage Members (kick/mute)
          SizedBox(
            width: 52,
            child: ElevatedButton(
              onPressed: _openManageMembers,
              style: secondaryButtonStyle,
              child: const Icon(Icons.manage_accounts_rounded, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: ElevatedButton(
              onPressed: _deleteTable,
              style: secondaryButtonStyle.copyWith(
                foregroundColor: WidgetStateProperty.all(Colors.red),
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
                  foregroundColor: WidgetStateProperty.all(Colors.red),
                ),
                child: const Icon(Icons.logout, size: 22),
              ),
            ),
          ],
        );
      } else if (status == 'pending') {
        if (_isInvited) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _acceptInvite,
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('Accept'),
                  style: buttonStyle,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 52,
                child: ElevatedButton(
                  onPressed: _declineInvite,
                  style: secondaryButtonStyle.copyWith(
                    foregroundColor: WidgetStateProperty.all(Colors.red),
                  ),
                  child: const Icon(Icons.close, size: 22),
                ),
              ),
            ],
          );
        }
        return ElevatedButton(
          onPressed: _cancelRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark
                ? Colors.orange[900]!.withOpacity(0.3)
                : Colors.orange[50],
            foregroundColor: isDark ? Colors.orange[300] : Colors.orange[800],
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          child: const Text('Request Pending'),
        );
      }
    }

    // ── Table status guard: table deleted or no longer open ──
    final effectiveStatus = _liveTableStatus ?? widget.table['status'];
    final isTableEnded =
        !_tableExists || (effectiveStatus != null && effectiveStatus != 'open');

    if (isTableEnded &&
        !_isHost &&
        (_membershipStatus == null ||
            !['approved', 'joined'].contains(_membershipStatus!['status']))) {
      return ElevatedButton(
        onPressed: null, // disabled
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
          foregroundColor: isDark ? Colors.grey[500] : Colors.grey[600],
          disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
          disabledForegroundColor: isDark ? Colors.grey[500] : Colors.grey[600],
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        child: const Text('Activity Ended'),
      );
    }

    // Join Button (Default) — full-width vibrant CTA
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _joinTable,
        style: buttonStyle,
        child: Text(
          'Join Table',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // LOGIC (unchanged)
  // ═══════════════════════════════════════════════

  void _openPendingRequests() {
    final tableTitle =
        widget.table['title'] ?? widget.table['location_name'] ?? 'Table';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PendingRequestsSheet(
        tableId: widget.table['id'],
        tableTitle: tableTitle,
      ),
    ).then((_) {
      _fetchPendingCount();
      _fetchMembers();
    });
  }

  void _openManageMembers() {
    final tableTitle =
        widget.table['title'] ?? widget.table['location_name'] ?? 'Table';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManageMembersSheet(
        tableId: widget.table['id'],
        tableTitle: tableTitle,
      ),
    ).then((_) => _fetchMembers());
  }

  void _openChat() {
    Navigator.pop(context);

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
        final message = result['message'] as String;
        final isPending = message.contains('Request sent');

        if (isPending) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.orange),
          );
          _checkMembershipStatus();
          _fetchPendingCount();
        } else {
          final venueName =
              widget.table['venue_name'] ??
              widget.table['title'] ??
              widget.table['location_name'] ??
              'Unknown Venue';

          Navigator.pop(context, true);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));

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

  Future<void> _acceptInvite() async {
    setState(() => _isLoading = true);
    final result = await _memberService.acceptInvite(widget.table['id']);

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'You\'re in! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        final venueName =
            widget.table['venue_name'] ??
            widget.table['title'] ??
            widget.table['location_name'] ??
            'Unknown Venue';

        Navigator.pop(context, true);
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to accept invite'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineInvite() async {
    setState(() => _isLoading = true);
    await _memberService.declineInvite(widget.table['id']);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite declined')));
      Navigator.pop(context, true);
    }
  }
}
