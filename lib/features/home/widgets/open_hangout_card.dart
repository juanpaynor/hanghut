import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// A rich hangout card for the Open Hangouts carousel.
/// Shows avatar stack, capacity badge, location/time, category pills,
/// and a "friends here" indicator.
class OpenHangoutCard extends StatefulWidget {
  final Map<String, dynamic> table;
  final VoidCallback onTap;

  const OpenHangoutCard({
    super.key,
    required this.table,
    required this.onTap,
  });

  @override
  State<OpenHangoutCard> createState() => _OpenHangoutCardState();
}

class _OpenHangoutCardState extends State<OpenHangoutCard> {
  double _scale = 1.0;

  // Data accessors
  String get _title => widget.table['title'] ?? 'Hangout';

  String? get _imageUrl {
    String? img = widget.table['marker_image_url'] ?? widget.table['image_url'];
    if (img == null &&
        widget.table['images'] != null &&
        (widget.table['images'] as List).isNotEmpty) {
      img = (widget.table['images'] as List).first as String?;
    }
    return img;
  }

  String get _venueName => widget.table['venue_name'] ?? '';

  String get _timeLabel {
    final raw = widget.table['scheduled_time'];
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString());
      final now = DateTime.now();
      final diff = dt.difference(now);

      if (diff.inMinutes < 60 && diff.inMinutes > 0) {
        return 'In ${diff.inMinutes}m';
      } else if (diff.inHours < 24 && diff.inHours > 0) {
        return 'In ${diff.inHours}h';
      } else if (dt.day == now.day &&
          dt.month == now.month &&
          dt.year == now.year) {
        return 'Today ${DateFormat.jm().format(dt)}';
      } else if (dt.day == now.day + 1 &&
          dt.month == now.month &&
          dt.year == now.year) {
        return 'Tomorrow ${DateFormat.jm().format(dt)}';
      }
      return DateFormat('MMM d, h:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  String get _activityType {
    final type = widget.table['activity_type'] as String?;
    return type?.toUpperCase() ?? '';
  }

  int get _memberCount => widget.table['member_count'] as int? ?? 0;
  int get _maxCapacity => widget.table['max_capacity'] as int? ?? 0;
  String get _availabilityState =>
      widget.table['availability_state'] as String? ?? 'available';

  List<String> get _memberAvatars {
    final avatars = widget.table['member_avatars'];
    if (avatars == null) return [];
    return List<String>.from(avatars);
  }

  List<Map<String, dynamic>> get _friendsHere {
    final friends = widget.table['friends_here'];
    if (friends == null) return [];
    return List<Map<String, dynamic>>.from(friends);
  }

  String? get _hostPhotoUrl => widget.table['host_photo_url'] as String?;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 200,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.black,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: _imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey[700]),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.deepPurple.shade700,
                              Colors.indigo.shade900,
                            ],
                          ),
                        ),
                      ),
              ),

              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.85),
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                ),
              ),

              // Top: Capacity badge
              Positioned(
                top: 10,
                right: 10,
                child: _buildCapacityBadge(),
              ),

              // Bottom content
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Avatar stack
                    _buildAvatarStack(),
                    const SizedBox(height: 8),

                    // Title
                    Text(
                      _title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Location + Time
                    if (_venueName.isNotEmpty || _timeLabel.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              [
                                if (_venueName.isNotEmpty) _venueName,
                                if (_timeLabel.isNotEmpty) _timeLabel,
                              ].join(' • '),
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                    // Category pill + friends indicator
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Category pill
                        if (_activityType.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              _activityType,
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // Friends indicator
                        if (_friendsHere.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF4CAF50),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_friendsHere.length} friend${_friendsHere.length > 1 ? 's' : ''}',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF81C784),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _buildCapacityBadge() {
    Color bgColor;
    String label;

    if (_availabilityState == 'full') {
      bgColor = Colors.red.shade600;
      label = 'FULL';
    } else if (_availabilityState == 'filling_up') {
      bgColor = const Color(0xFFFF9800);
      label = '$_memberCount/$_maxCapacity 🔥';
    } else {
      bgColor = const Color(0xFFFFD700);
      label =
          _maxCapacity > 0 ? '$_memberCount/$_maxCapacity' : 'OPEN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: bgColor == const Color(0xFFFFD700)
              ? Colors.black
              : Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildAvatarStack() {
    // Combine host + member avatars
    final allAvatars = <String?>[];
    if (_hostPhotoUrl != null) allAvatars.add(_hostPhotoUrl);
    for (final url in _memberAvatars) {
      if (!allAvatars.contains(url)) allAvatars.add(url);
    }

    final maxShow = 4;
    final displayAvatars = allAvatars.take(maxShow).toList();
    final overflow = allAvatars.length - maxShow;

    if (displayAvatars.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          for (int i = 0; i < displayAvatars.length; i++)
            Positioned(
              left: i * 18.0,
              child: _MiniAvatar(
                url: displayAvatars[i],
                size: 28,
                isHost: i == 0 && _hostPhotoUrl != null,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: displayAvatars.length * 18.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small circular avatar for the stack
class _MiniAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final bool isHost;

  const _MiniAvatar({
    this.url,
    this.size = 28,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isHost ? const Color(0xFFFFD700) : Colors.white,
          width: isHost ? 2 : 1.5,
        ),
        color: Colors.grey[700],
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
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
