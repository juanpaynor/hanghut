import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/widgets/avatar_stack.dart';
import 'package:bitemates/core/services/event_interest_service.dart';
import 'package:bitemates/features/ticketing/models/event_social_proof.dart';

/// "369 going" + faces, or "Be the first to go" — the one line that tells a
/// viewer whether anyone is actually going.
///
/// The mirror of [HangoutGoingRow], shared by the event modal, the Discover
/// cards and the map cluster sheets so all of them count the same way. Always
/// renders: hiding it on a quiet event is what made every event look equally
/// dead.
class EventGoingRow extends StatelessWidget {
  final EventSocialProof proof;

  final double avatarSize;
  final Color? background;
  final TextStyle? labelStyle;

  /// Uses the short label ("Be first" rather than "Be the first to go") for
  /// narrow slots such as a card's trailing column.
  final bool compact;

  const EventGoingRow({
    super.key,
    required this.proof,
    this.avatarSize = 26,
    this.background,
    this.labelStyle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : Colors.black54;
    final suffix = proof.interestedSuffix;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (proof.avatars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AvatarStack(
              avatarUrls: proof.avatars,
              // The true headcount, not avatars.length — so three faces on a
              // 369-person event read "+366" instead of implying three people.
              totalCount: proof.goingCount,
              size: avatarSize,
              borderColor: background ?? theme.scaffoldBackgroundColor,
              borderWidth: 2,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              Icons.people_outline,
              size: avatarSize * 0.72,
              color: muted,
            ),
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
                  // A quiet event is stated plainly, not shouted in the accent
                  // colour — the accent is for the people who did turn up.
                  color: proof.isEmpty
                      ? muted
                      : (isDark ? Colors.white : Colors.black87),
                ),
          ),
        ),
        if (suffix != null) ...[
          Text('  ·  ', style: GoogleFonts.inter(fontSize: 13, color: muted)),
          Text(
            suffix,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// The cheap first action. Toggles interest optimistically so the tap feels
/// instant, and rolls back if the write fails.
///
/// Hidden entirely for a ticket holder: they are already going, and offering
/// "I'm interested" to someone who paid would read as a downgrade.
class EventInterestedButton extends StatefulWidget {
  final String eventId;
  final EventSocialProof proof;

  /// Called with the updated proof so the parent can refresh its own copy.
  final ValueChanged<EventSocialProof>? onChanged;

  final bool compact;

  const EventInterestedButton({
    super.key,
    required this.eventId,
    required this.proof,
    this.onChanged,
    this.compact = false,
  });

  @override
  State<EventInterestedButton> createState() => _EventInterestedButtonState();
}

class _EventInterestedButtonState extends State<EventInterestedButton> {
  final _service = EventInterestService.instance;
  bool _busy = false;
  late EventSocialProof _proof;

  @override
  void initState() {
    super.initState();
    _proof = widget.proof;
  }

  @override
  void didUpdateWidget(EventInterestedButton old) {
    super.didUpdateWidget(old);
    // Parent refetched — adopt the server's version, unless our own write is
    // still in flight and would be clobbered by it.
    if (!_busy && widget.proof != old.proof) _proof = widget.proof;
  }

  bool get _isInterested => _proof.viewerState == EventViewerState.interested;

  Future<void> _toggle() async {
    if (_busy) return;
    final wasInterested = _isInterested;
    final before = _proof;

    setState(() {
      _busy = true;
      _proof = _proof.copyWith(
        interestedCount: (_proof.interestedCount + (wasInterested ? -1 : 1))
            .clamp(0, 1 << 30),
        viewerState:
            wasInterested ? EventViewerState.none : EventViewerState.interested,
      );
    });
    widget.onChanged?.call(_proof);

    final ok = wasInterested
        ? await _service.removeInterest(widget.eventId)
        : await _service.markInterested(widget.eventId);

    if (!mounted) return;
    setState(() {
      _busy = false;
      // Roll back — never leave a state on screen that we did not save.
      if (!ok) _proof = before;
    });
    if (!ok) {
      widget.onChanged?.call(before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // A ticket holder is already going; there is nothing to offer them.
    if (!_proof.canMarkInterested && !_isInterested) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;

    final label = _isInterested ? 'Interested' : "I'm interested";
    final fg =
        _isInterested ? primary : (isDark ? Colors.white70 : Colors.black87);

    return TextButton.icon(
      onPressed: _busy ? null : _toggle,
      // Icons.star / star_outline are both present in release 11305a4. A glyph
      // that is not renders as "?" in a Shorebird patch, which ships Dart only.
      icon: Icon(
        _isInterested ? Icons.star : Icons.star_outline,
        size: widget.compact ? 16 : 18,
        color: fg,
      ),
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
          vertical: widget.compact ? 4 : 8,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: _isInterested
            ? primary.withValues(alpha: 0.10)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: _isInterested
                ? primary.withValues(alpha: 0.5)
                : (isDark ? Colors.white24 : Colors.black26),
          ),
        ),
      ),
    );
  }
}
