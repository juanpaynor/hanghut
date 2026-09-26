import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/widgets/avatar_stack.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/map/models/hangout_social_proof.dart';

/// "3 going" + faces, or "Be the first to join" — the one line that tells a
/// viewer whether anyone is actually coming.
///
/// Shared by the feed card, the Explore card and the detail modal so all three
/// count the same way. Always renders: hiding it when a hangout is empty is
/// what made an empty hangout look identical to a full one.
class HangoutGoingRow extends StatelessWidget {
  final HangoutSocialProof proof;

  /// Shows the "Needs N more" ask when the host set a real capacity.
  final bool showAsk;

  final double avatarSize;
  final Color? background;
  final TextStyle? labelStyle;

  /// Uses the short label ("Be first" rather than "Be the first to join") for
  /// narrow slots such as a feed card's trailing column.
  final bool compact;

  const HangoutGoingRow({
    super.key,
    required this.proof,
    this.showAsk = true,
    this.avatarSize = 26,
    this.background,
    this.labelStyle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;
    final muted = isDark ? Colors.white70 : Colors.black54;

    final ask = showAsk ? proof.needsMoreLabel : null;
    final suffix = proof.interestedSuffix;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (proof.avatars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AvatarStack(
              avatarUrls: proof.avatars,
              totalCount: proof.goingCount,
              size: avatarSize,
              borderColor: background ?? theme.scaffoldBackgroundColor,
              borderWidth: 2,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.people_outline, size: avatarSize * 0.72,
                color: muted),
          ),
        Flexible(
          child: Text(
            compact ? proof.goingLabelCompact : proof.goingLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle ??
                GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  // An empty hangout is stated plainly, not shouted in the
                  // accent colour — the accent is for the people who did come.
                  color: proof.isEmpty ? muted : (isDark ? Colors.white : Colors.black87),
                ),
          ),
        ),
        if (suffix != null) ...[
          Text('  ·  ', style: GoogleFonts.inter(fontSize: 13, color: muted)),
          Text(suffix,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w500, color: muted)),
        ],
        if (ask != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ask,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The lighter first step. Toggles interest optimistically so the tap feels
/// instant, and rolls back if the write fails.
class InterestedButton extends StatefulWidget {
  final String tableId;
  final HangoutSocialProof proof;

  /// Called with the updated proof so the parent can refresh its own copy.
  final ValueChanged<HangoutSocialProof>? onChanged;

  final bool compact;

  const InterestedButton({
    super.key,
    required this.tableId,
    required this.proof,
    this.onChanged,
    this.compact = false,
  });

  @override
  State<InterestedButton> createState() => _InterestedButtonState();
}

class _InterestedButtonState extends State<InterestedButton> {
  final _service = TableMemberService();
  bool _busy = false;
  late HangoutSocialProof _proof;

  @override
  void initState() {
    super.initState();
    _proof = widget.proof;
  }

  @override
  void didUpdateWidget(InterestedButton old) {
    super.didUpdateWidget(old);
    // Parent refetched — adopt the server's version unless a write is in flight.
    if (!_busy && widget.proof != old.proof) _proof = widget.proof;
  }

  bool get _isInterested =>
      _proof.viewerState == HangoutViewerState.interested;

  Future<void> _toggle() async {
    if (_busy) return;
    final wasInterested = _isInterested;
    final before = _proof;

    setState(() {
      _busy = true;
      _proof = _proof.copyWith(
        interestedCount:
            (_proof.interestedCount + (wasInterested ? -1 : 1)).clamp(0, 1 << 30),
        viewerState: wasInterested
            ? HangoutViewerState.none
            : HangoutViewerState.interested,
      );
    });
    widget.onChanged?.call(_proof);

    bool ok;
    String? message;
    if (wasInterested) {
      ok = await _service.removeInterest(widget.tableId);
    } else {
      final res = await _service.markInterested(widget.tableId);
      ok = res['success'] == true;
      message = res['message'] as String?;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _proof = before; // roll back — never show a state we didn't save
    });
    if (!ok) widget.onChanged?.call(before);

    if (!ok && message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to offer someone who already holds a spot, or the host.
    if (!_proof.canMarkInterested && !_isInterested) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;

    final label = _isInterested ? 'Interested' : "I'm interested";
    final fg = _isInterested
        ? primary
        : (isDark ? Colors.white70 : Colors.black87);

    return TextButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(_isInterested ? Icons.star : Icons.star_outline,
          size: widget.compact ? 16 : 18, color: fg),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: widget.compact ? 12 : 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: widget.compact ? 4 : 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor:
            _isInterested ? primary.withOpacity(0.10) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: _isInterested
                ? primary.withOpacity(0.5)
                : (isDark ? Colors.white24 : Colors.black26),
          ),
        ),
      ),
    );
  }
}
