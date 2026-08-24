import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/host/screens/create_event_screen.dart';

/// Per-event management hub for hosts (team_comms #210 IA):
/// Overview (stats) → Tickets (tiers) → Guests (approvals inbox) + Edit.
/// Replaces tapping a card straight into the edit wizard.
class HostEventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const HostEventDetailScreen({super.key, required this.event});

  @override
  State<HostEventDetailScreen> createState() => _HostEventDetailScreenState();
}

class _HostEventDetailScreenState extends State<HostEventDetailScreen> {
  final _hostService = HostService();
  late Map<String, dynamic> _event;
  int _section = 0;
  bool _busy = false;
  bool _changed = false; // whether to tell the dashboard to refresh on pop

  @override
  void initState() {
    super.initState();
    _event = Map<String, dynamic>.from(widget.event);
    _loadSoldCount();
  }

  /// The Overview is a SALES view, so it uses the canonical "really sold" count
  /// — paid tickets only (status in valid/used) via get_event_paid_count — not
  /// the availability count (which includes reserved/pending). Overwrites the
  /// in-memory event so the stats reflect actual sales (team_comms #230).
  Future<void> _loadSoldCount() async {
    try {
      final count = await SupabaseConfig.client.rpc(
        'get_event_paid_count',
        params: {'p_event_id': _eventId},
      );
      final sold = (count as num?)?.toInt();
      if (sold != null && mounted) {
        setState(() => _event = {..._event, 'tickets_sold': sold});
      }
    } catch (e) {
      debugPrint('⚠️ get_event_paid_count failed: $e');
    }
  }

  String get _eventId => _event['id'] as String;
  bool get _isLive => _event['status'] == 'active';
  bool get _isDraft => _event['status'] == 'draft';
  bool get _requiresApproval => _event['require_approval'] == true;

  Future<void> _refresh() async {
    final fresh = await _hostService.getEvent(_eventId);
    if (fresh != null && mounted) setState(() => _event = fresh);
    // getEvent returns the stale tickets_sold column — re-sync the live count.
    await _loadSoldCount();
  }

  Future<void> _openEditor() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(
          partnerId: _event['organizer_id'] as String,
          existingEvent: _event,
        ),
      ),
    );
    if (saved == true) {
      _changed = true;
      await _refresh();
    }
  }

  Future<void> _togglePublish() async {
    setState(() => _busy = true);
    try {
      final res = await _hostService.setEventPublished(
        eventId: _eventId,
        publish: _isDraft,
      );
      _changed = true;
      if (mounted) {
        setState(() {
          // RPC returns draft|published; reflect it as the raw status we read.
          _event['status'] = res['status'] == 'published' ? 'active' : 'draft';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isLive ? 'Event published' : 'Event unpublished'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e,
            fallbackMessage:
                'Unable to change publish state. Events with sales can\'t be unpublished — use cancel instead.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (String, Color) get _statusChip {
    switch (_event['status']) {
      case 'active':
        return ('Live', Colors.green);
      case 'draft':
        return ('Draft', Colors.grey);
      case 'sold_out':
        return ('Sold out', Colors.blue);
      case 'cancelled':
        return ('Cancelled', Colors.red);
      case 'completed':
        return ('Completed', Colors.grey);
      case 'paused':
        return ('Paused', Colors.orange);
      default:
        return ('${_event['status'] ?? 'Draft'}', Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = _statusChip;
    final cover = _event['cover_image_url'] as String?;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
          title: Text('Manage event',
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          actions: [
            TextButton.icon(
              onPressed: _busy ? null : _openEditor,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text('Edit', style: GoogleFonts.inter(fontSize: 13)),
            ),
          ],
        ),
        body: Column(
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: (cover != null && cover.isNotEmpty)
                          ? Image.network(cover, fit: BoxFit.cover)
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_outlined,
                                  size: 40, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_event['title'] ?? '',
                            style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(chipLabel,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: chipColor)),
                      ),
                    ],
                  ),
                  if (_isDraft || _isLive) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _isLive
                          ? OutlinedButton.icon(
                              onPressed: _busy ? null : _togglePublish,
                              icon: const Icon(Icons.unpublished_outlined,
                                  size: 18),
                              label: const Text('Unpublish'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                side: BorderSide(color: Colors.grey[400]!),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: _busy ? null : _togglePublish,
                              icon: const Icon(Icons.publish, size: 18),
                              label: const Text('Publish event'),
                            ),
                    ),
                  ],
                ],
              ),
            ),
            // Segmented control
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Overview')),
                  ButtonSegment(value: 1, label: Text('Tickets')),
                  ButtonSegment(value: 2, label: Text('Attendees')),
                ],
                selected: {_section},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _section = s.first),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _section,
                children: [
                  _OverviewSection(event: _event),
                  _TicketsSection(event: _event, onEdit: _openEditor),
                  _GuestsSection(
                    eventId: _eventId,
                    requiresApproval: _requiresApproval,
                    hostService: _hostService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overview ────────────────────────────────────────────────────────────────
class _OverviewSection extends StatelessWidget {
  final Map<String, dynamic> event;
  const _OverviewSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final capacity = (event['capacity'] as num?)?.toInt() ?? 0;
    final sold = (event['tickets_sold'] as num?)?.toInt() ?? 0;
    final tiers = (event['ticket_tiers'] as List?) ?? [];
    final start = DateTime.tryParse(event['start_datetime'] ?? '')?.toLocal();
    final salesEnd =
        DateTime.tryParse(event['sales_end_datetime'] ?? '')?.toLocal();
    final df = DateFormat('EEE, MMM d, y • h:mm a');

    // Revenue estimate from tier price × sold (display-only).
    num revenue = 0;
    for (final t in tiers) {
      final m = t as Map<String, dynamic>;
      revenue += ((m['price'] as num?) ?? 0) * ((m['quantity_sold'] as num?) ?? 0);
    }
    final pct = capacity == 0 ? 0.0 : (sold / capacity).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
                child: _statCard('Tickets sold', '$sold / $capacity',
                    Icons.confirmation_number_outlined)),
            const SizedBox(width: 12),
            Expanded(
                child: _statCard('Revenue', '₱${revenue.toStringAsFixed(0)}',
                    Icons.payments_outlined)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDeco,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Capacity',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct.toDouble(),
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Text('${(pct * 100).toStringAsFixed(0)}% sold',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _infoTile(Icons.event, 'Starts', start == null ? '—' : df.format(start)),
        _infoTile(Icons.timer_off_outlined, 'Sales end',
            salesEnd == null ? 'At event start' : df.format(salesEnd)),
        _infoTile(
            Icons.place_outlined,
            'Where',
            [event['venue_name'], event['address']]
                .where((s) => s != null && (s as String).trim().isNotEmpty)
                .join(' · ')),
        _infoTile(
            Icons.how_to_reg_outlined,
            'Registration',
            event['require_approval'] == true
                ? 'Approval required'
                : 'Open (instant)'),
        _infoTile(Icons.local_activity_outlined, 'Ticket types',
            '${tiers.length}'),
      ],
    );
  }

  static final _cardDeco = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0x11000000)),
  );

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w700)),
          Text(label,
              style:
                  GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
          const Spacer(),
          Flexible(
            child: Text(value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Tickets ─────────────────────────────────────────────────────────────────
class _TicketsSection extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onEdit;
  const _TicketsSection({required this.event, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final tiers = List<Map<String, dynamic>>.from(
        (event['ticket_tiers'] as List?) ?? [])
      ..sort((a, b) =>
          ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0)));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...tiers.map((t) {
          final sold = (t['quantity_sold'] as num?)?.toInt() ?? 0;
          final total = (t['quantity_total'] as num?)?.toInt() ?? 0;
          final price = (t['price'] as num?) ?? 0;
          final pct = total == 0 ? 0.0 : (sold / total).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x11000000)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t['name'] ?? 'Ticket',
                          style: GoogleFonts.inter(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    Text('₱${price.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct.toDouble(),
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text('$sold / $total sold',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Manage tickets'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.primaryColor),
          ),
        ),
      ],
    );
  }
}

// ── Guests / approvals ──────────────────────────────────────────────────────
class _GuestsSection extends StatefulWidget {
  final String eventId;
  final bool requiresApproval;
  final HostService hostService;
  const _GuestsSection({
    required this.eventId,
    required this.requiresApproval,
    required this.hostService,
  });

  @override
  State<_GuestsSection> createState() => _GuestsSectionState();
}

class _GuestsSectionState extends State<_GuestsSection> {
  // (attendees from tickets, pending registrations from event_registrations)
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _future;
  String? _busyId; // registration id currently being actioned

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>
      _load() async {
    // Load independently so one failing call can't blank the whole tab.
    final results = await Future.wait([
      widget.hostService
          .getEventAttendees(widget.eventId)
          .then((r) => List<Map<String, dynamic>>.from(
              (r)['attendees'] as List? ?? const []))
          .catchError((e) {
        debugPrint('getEventAttendees failed: $e');
        return <Map<String, dynamic>>[];
      }),
      widget.hostService
          .getEventRegistrations(widget.eventId, status: 'pending')
          .catchError((e) {
        debugPrint('getEventRegistrations failed: $e');
        return <Map<String, dynamic>>[];
      }),
    ]);
    return (results[0], results[1]);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _review(Map<String, dynamic> reg, bool approve) async {
    final id = reg['id'] as String;
    String? reason;

    if (!approve) {
      // Rejection reason is optional (feeds {{reason}} in the email if the
      // organizer set custom copy). Let the host add one or skip.
      final controller = TextEditingController();
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject request?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The guest will be notified.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'Reason (optional)', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reject',
                    style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (proceed != true) return;
      reason = controller.text;
    } else {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approve request?'),
          content: const Text(
              'The guest will be notified. For free events their ticket is issued now; for paid events they\'ll be able to buy.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _busyId = id);
    try {
      await widget.hostService.reviewEventRegistration(
        registrationId: id,
        approve: approve,
        rejectionReason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? 'Request approved' : 'Request rejected'),
          backgroundColor: Colors.green,
        ));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Unable to review this request.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<
          (List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _emptyState(
                'Couldn\'t load attendees', Icons.error_outline);
          }
          final attendees = snap.data?.$1 ?? [];
          final pending = snap.data?.$2 ?? [];
          final checkedIn =
              attendees.where((a) => a['status_label'] == 'checked_in').length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.requiresApproval && pending.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.blue[700]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Approve to let guests in (free events get their ticket right away; paid events can then buy). Rejecting notifies them.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.blue[900]),
                        ),
                      ),
                    ],
                  ),
                ),
              if (pending.isEmpty && attendees.isEmpty)
                _emptyState('No attendees yet', Icons.people_outline),
              if (pending.isNotEmpty) ...[
                _sectionLabel('Pending requests (${pending.length})'),
                ...pending.map(_guestTile),
                const SizedBox(height: 16),
              ],
              if (attendees.isNotEmpty) ...[
                _sectionLabel(
                    'Attendees (${attendees.length}) · $checkedIn checked in'),
                ...attendees.map(_attendeeTile),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(icon, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Center(
              child: Text(text,
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500])),
            ),
          ],
        ),
      );

  Widget _attendeeTile(Map<String, dynamic> t) {
    final name = (t['name'] as String?)?.trim();
    final email = (t['email'] as String?)?.trim();
    final avatarUrl = (t['avatar_url'] as String?)?.trim();
    final tier = (t['tier'] as Map<String, dynamic>?)?['name'] as String?;
    final ticketNo = (t['ticket_number'] as String?)?.trim();
    final (label, color) = _attendeeChip(t['status_label'] as String?);
    final display = (name != null && name.isNotEmpty)
        ? name
        : (email != null && email.isNotEmpty ? email : 'Guest');
    final subtitle = [tier, ticketNo]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');

    return GestureDetector(
      onTap: () => _showAttendeeDetail(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x11000000)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(
                      display.characters.first.toUpperCase(),
                      style: GoogleFonts.inter(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showAttendeeDetail(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AttendeeDetailSheet(attendee: t),
    );
  }

  /// Attendee status labels locked with web (#217): going→Going,
  /// checked_in→Checked in, refunded→Refunded.
  (String, Color) _attendeeChip(String? statusLabel) {
    switch (statusLabel) {
      case 'checked_in':
        return ('Checked in', Colors.green);
      case 'refunded':
        return ('Refunded', Colors.grey);
      default:
        return ('Going', Colors.blueGrey);
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.5)),
      );

  Widget _guestTile(Map<String, dynamic> r) {
    final name = (r['guest_name'] as String?)?.trim();
    final email = (r['guest_email'] as String?)?.trim();
    final tier = (r['tier'] as Map<String, dynamic>?)?['name'] as String?;
    final status = r['status'] as String? ?? 'pending';
    final (label, color) = _regStatusChip(status);
    final display = (name != null && name.isNotEmpty)
        ? name
        : (email != null && email.isNotEmpty ? email : 'Guest');
    final isPending = status == 'pending';
    final rowBusy = _busyId == r['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                child: Text(
                  display.characters.first.toUpperCase(),
                  style: GoogleFonts.inter(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (tier != null)
                      Text(tier,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            rowBusy
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _review(r, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _review(r, true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
          ],
        ],
      ),
    );
  }

  (String, Color) _regStatusChip(String status) {
    switch (status) {
      case 'approved':
      case 'auto_approved':
        return ('Approved', Colors.green);
      case 'rejected':
        return ('Rejected', Colors.red);
      case 'cancelled':
        return ('Cancelled', Colors.grey);
      default:
        return ('Pending', Colors.orange);
    }
  }
}

/// Full detail for one attendee, from get_event_attendees (#217).
class _AttendeeDetailSheet extends StatelessWidget {
  final Map<String, dynamic> attendee;
  const _AttendeeDetailSheet({required this.attendee});

  String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? _money(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v : num.tryParse(v.toString());
    return n == null ? null : '₱${n.toStringAsFixed(2)}';
  }

  String? _dateTime(dynamic v) {
    final s = _str(v);
    if (s == null) return null;
    final d = DateTime.tryParse(s)?.toLocal();
    return d == null ? null : DateFormat('MMM d, y • h:mm a').format(d);
  }

  (String, Color) _chip(String? statusLabel) {
    switch (statusLabel) {
      case 'checked_in':
        return ('Checked in', Colors.green);
      case 'refunded':
        return ('Refunded', Colors.grey);
      default:
        return ('Going', Colors.blueGrey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = attendee;
    final name = _str(t['name']);
    final email = _str(t['email']);
    final phone = _str(t['phone']);
    final avatarUrl = _str(t['avatar_url']);
    final isGuest = t['source'] == 'guest';
    final tier = t['tier'] as Map<String, dynamic>?;
    final (chipLabel, chipColor) = _chip(t['status_label'] as String?);
    final display = name ?? email ?? 'Guest';
    final refunded = _money(t['refunded_amount']);
    final hasRefund = refunded != null &&
        ((t['refunded_amount'] as num?) ?? 0) > 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                  backgroundImage: avatarUrl != null
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? Text(display.characters.first.toUpperCase(),
                          style: GoogleFonts.inter(
                              fontSize: 20,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(display,
                          style: GoogleFonts.inter(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(isGuest ? 'Guest checkout' : 'Account',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: chipColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(chipLabel,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: chipColor)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _section('Contact', [
              _row('Email', email),
              _row('Phone', phone),
            ]),
            _section('Ticket', [
              _row('Ticket #', _str(t['ticket_number'])),
              _row('Tier', _str(tier?['name'])),
              _row('Tier price', _money(tier?['price'])),
              _row('Seat', _str(t['seat_info'])),
              if (_str(t['registration_id']) != null)
                _row('Entry', 'Via approval request'),
            ]),
            _section('Payment', [
              _row('Amount', _money(t['amount'])),
              _row('Status', _str(t['payment_status'])),
              _row('Method', _str(t['payment_method'])),
              _row('Invoice', _str(t['invoice_id'])),
              if (hasRefund) _row('Refunded', refunded),
              if (hasRefund) _row('Refunded on', _dateTime(t['refunded_at'])),
            ]),
            _section('Timeline', [
              _row('Purchased', _dateTime(t['created_at'])),
              _row('Checked in', _dateTime(t['checked_in_at'])),
            ]),
          ],
        ),
      ),
    );
  }

  /// A titled group; skips itself entirely if every row is empty.
  Widget _section(String title, List<Widget?> rows) {
    final visible = rows.whereType<Widget>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        ...visible,
        const SizedBox(height: 18),
      ],
    );
  }

  /// Returns null (so the section can hide it) when the value is empty.
  Widget? _row(String label, String? value) {
    if (value == null || value.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style:
                    GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
