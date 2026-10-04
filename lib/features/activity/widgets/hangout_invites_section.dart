import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/table_member_service.dart';

/// "You're invited" — the surface an invite had nowhere to land.
///
/// `table_members.status = 'invited'` was a legal value that no screen read
/// and no query returned, so an invited user's only signal was a push
/// notification, and tapping Join told them they were already a member. This
/// section plus [TableMemberService.getMyInvites] is the other half.
///
/// Renders nothing at all when there are no invites — it sits above a list
/// that is itself usually empty, and an empty header above an empty list just
/// doubles the emptiness.
class HangoutInvitesSection extends StatefulWidget {
  /// Called after an invite is accepted or declined so the parent can reload
  /// its own list — an accepted invite becomes a joined hangout down there.
  final VoidCallback? onChanged;

  const HangoutInvitesSection({super.key, this.onChanged});

  @override
  State<HangoutInvitesSection> createState() => HangoutInvitesSectionState();
}

class HangoutInvitesSectionState extends State<HangoutInvitesSection> {
  final _memberService = TableMemberService();

  List<Map<String, dynamic>> _invites = [];
  bool _loading = true;

  /// Ids with a write in flight, so a double-tap cannot double-join.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final invites = await _memberService.getMyInvites();
    if (!mounted) return;
    setState(() {
      _invites = invites;
      _loading = false;
    });
  }

  Future<void> _accept(Map<String, dynamic> hangout) async {
    final id = hangout['id']?.toString();
    if (id == null || _busy.contains(id)) return;
    setState(() => _busy.add(id));

    // The real join path: capacity, approval and distance are enforced there,
    // not here. An invite does not reserve a seat, so this can legitimately
    // fail with "This hangout is full".
    final res = await _memberService.joinTable(id);
    if (!mounted) return;
    setState(() => _busy.remove(id));

    final ok = res['success'] == true;
    if (ok) {
      setState(() => _invites.removeWhere((h) => h['id']?.toString() == id));
      widget.onChanged?.call();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['message']?.toString() ??
              (ok ? 'Joined' : "Couldn't join. Please try again."),
        ),
      ),
    );
  }

  Future<void> _decline(Map<String, dynamic> hangout) async {
    final id = hangout['id']?.toString();
    if (id == null || _busy.contains(id)) return;
    setState(() => _busy.add(id));

    final res = await _memberService.declineInvite(id);
    if (!mounted) return;
    final ok = res['success'] == true;
    setState(() {
      _busy.remove(id);
      if (ok) _invites.removeWhere((h) => h['id']?.toString() == id);
    });
    if (ok) {
      widget.onChanged?.call();
      return;
    }
    // declineInvite now reports a 0-row update as a failure rather than a
    // silent success, so say so instead of leaving the card sitting there
    // looking ignored.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message']?.toString() ?? "Couldn't decline that."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _invites.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              // Icons.mail_outline is present in release 11305a4 — a glyph
              // that is not renders as "?" in a Shorebird patch.
              Icon(Icons.mail_outline, size: 18, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                _invites.length == 1
                    ? "You're invited"
                    : "You're invited (${_invites.length})",
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        ..._invites.map((h) => _InviteCard(
              hangout: h,
              busy: _busy.contains(h['id']?.toString()),
              onAccept: () => _accept(h),
              onDecline: () => _decline(h),
            )),
        const SizedBox(height: 8),
        Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> hangout;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InviteCard({
    required this.hangout,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;

    final title = (hangout['title']?.toString().trim().isNotEmpty ?? false)
        ? hangout['title'].toString()
        : 'Hangout';
    final venue =
        hangout['location_name']?.toString() ?? hangout['city']?.toString();
    final when = DateTime.tryParse(hangout['datetime']?.toString() ?? '');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (when != null) DateFormat('EEE d MMM, h:mm a').format(when),
              if (venue != null && venue.isNotEmpty) venue,
            ].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          "I'm in",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: busy ? null : onDecline,
                child: Text(
                  'No thanks',
                  style: GoogleFonts.inter(fontSize: 13, color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
