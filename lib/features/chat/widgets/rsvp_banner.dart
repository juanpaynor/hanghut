import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Collapsible RSVP banner shown in table chats below the header.
/// Shows 3 buttons (Going / Maybe / Can't) in expanded state,
/// and a compact pill in collapsed state.
class RsvpBanner extends StatefulWidget {
  final String tableId;
  final String? currentRsvpStatus; // 'none', 'going', 'maybe', 'not_going'
  final int goingCount;
  final int maybeCount;
  final int notGoingCount;
  final Function(String status) onRsvpChanged;

  const RsvpBanner({
    super.key,
    required this.tableId,
    this.currentRsvpStatus,
    this.goingCount = 0,
    this.maybeCount = 0,
    this.notGoingCount = 0,
    required this.onRsvpChanged,
  });

  @override
  State<RsvpBanner> createState() => _RsvpBannerState();
}

class _RsvpBannerState extends State<RsvpBanner>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _loadCollapseState();
  }

  Future<void> _loadCollapseState() async {
    final prefs = await SharedPreferences.getInstance();
    final collapsed = prefs.getBool('rsvp_collapsed_${widget.tableId}') ?? false;
    if (collapsed) {
      setState(() => _isExpanded = false);
    } else {
      _animController.value = 1.0;
    }
  }

  Future<void> _toggleExpanded() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();

    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
    await prefs.setBool('rsvp_collapsed_${widget.tableId}', !_isExpanded);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'going':
        return const Color(0xFF10B981); // emerald
      case 'maybe':
        return const Color(0xFFF59E0B); // amber
      case 'not_going':
        return const Color(0xFFEF4444); // red
      default:
        return Colors.grey;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'going':
        return '✅';
      case 'maybe':
        return '🤔';
      case 'not_going':
        return '❌';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentStatus = widget.currentRsvpStatus ?? 'none';

    return GestureDetector(
      onTap: _toggleExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: _isExpanded ? 12 : 8,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : const Color(0xFFF1F5F9),
            ),
          ),
        ),
        child: _isExpanded ? _buildExpanded(currentStatus, isDark) : _buildCollapsed(isDark),
      ),
    );
  }

  Widget _buildCollapsed(bool isDark) {
    final parts = <String>[];
    if (widget.goingCount > 0) parts.add('${widget.goingCount} Going');
    if (widget.maybeCount > 0) parts.add('${widget.maybeCount} Maybe');
    if (parts.isEmpty) parts.add('RSVP');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey[800]!.withOpacity(0.6)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '📋 ${parts.join(' · ')}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more,
                size: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(String currentStatus, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapse handle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Are you going?',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_less,
              size: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // RSVP buttons row
        Row(
          children: [
            _buildRsvpButton(
              'going',
              '✅ Going',
              currentStatus == 'going',
              widget.goingCount,
              isDark,
            ),
            const SizedBox(width: 8),
            _buildRsvpButton(
              'maybe',
              '🤔 Maybe',
              currentStatus == 'maybe',
              widget.maybeCount,
              isDark,
            ),
            const SizedBox(width: 8),
            _buildRsvpButton(
              'not_going',
              "❌ Can't",
              currentStatus == 'not_going',
              widget.notGoingCount,
              isDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRsvpButton(
    String status,
    String label,
    bool isSelected,
    int count,
    bool isDark,
  ) {
    final color = _statusColor(status);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          // Toggle: if already selected, set to 'none'
          if (isSelected) {
            widget.onRsvpChanged('none');
          } else {
            widget.onRsvpChanged(status);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(isDark ? 0.25 : 0.1)
                : isDark
                    ? Colors.grey[850]
                    : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color.withOpacity(0.6)
                  : isDark
                      ? Colors.grey[700]!
                      : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? color
                      : isDark
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? color
                        : isDark
                            ? Colors.grey[500]
                            : Colors.grey[400],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
