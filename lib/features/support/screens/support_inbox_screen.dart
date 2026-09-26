import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/support/models/support_models.dart';
import 'package:bitemates/features/support/screens/support_entry.dart';
import 'package:bitemates/features/support/screens/support_thread_screen.dart';
import 'package:bitemates/features/support/services/support_service.dart';

/// All of the user's support conversations in one place.
///
/// The main inbox shows ONE "HangHut Support" row that lands here, rather than
/// one row per ticket (Rich, 2026-09-15): a user who has contacted support
/// three times should not see three identical conversations, and a finished
/// thread should read as finished, not as a chat waiting for a reply.
///
/// Active threads (open / pending) sit on top; finished ones (resolved /
/// closed) below, dimmed. One active thread at a time is preserved here as it
/// is in [SupportEntry]: the bottom button continues the active thread when
/// there is one and starts a new one only when there is not.
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen>
    with WidgetsBindingObserver {
  final _service = SupportService();

  List<SupportTicket> _tickets = [];
  Map<String, int> _unread = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// An agent reply while this list is in the background changes a badge and
  /// possibly a status; refetch on the way back rather than showing stale rows.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.myTickets(),
        _service.unreadByTicket(),
      ]);
      if (!mounted) return;
      setState(() {
        _tickets = results[0] as List<SupportTicket>;
        _unread = results[1] as Map<String, int>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorHandler.getUserMessage(e,
            fallback: 'Could not load your conversations');
      });
    }
  }

  Future<void> _openThread(SupportTicket t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportThreadScreen(ticketId: t.id, initialTicket: t),
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _primaryAction() async {
    final active = _tickets.where((t) => t.isActive);
    if (active.isNotEmpty) {
      await _openThread(active.first);
      return;
    }
    await SupportEntry.composeNew(context, openedFromPath: 'app/support');
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _tickets.where((t) => t.isActive).toList();
    final finished = _tickets.where((t) => t.isFinished).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('HangHut Support',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(theme, active, finished),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _primaryAction,
              // add_comment_outlined is NOT in release 11305a4, so it would
              // render as a "?" box in a Shorebird patch — patches ship Dart,
              // never new icon-font glyphs. add_circle_outline is in the
              // release and says the same thing.
              icon: Icon(active.isEmpty
                  ? Icons.add_circle_outline
                  : Icons.chat_bubble_outline),
              label: Text(active.isEmpty
                  ? 'New conversation'
                  : 'Continue conversation'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<SupportTicket> active,
    List<SupportTicket> finished,
  ) {
    if (_loading && _tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.support_agent,
                  size: 48, color: theme.primaryColor.withValues(alpha: 0.7)),
              const SizedBox(height: 14),
              const Text('No conversations yet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Need help with a ticket, an event or your account? '
                'Start a conversation and we will reply here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5, color: theme.textTheme.bodySmall?.color),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (active.isNotEmpty) ...[
            _sectionLabel(theme, 'Active'),
            for (final t in active) _TicketRow(
              ticket: t,
              unread: _unread[t.id] ?? 0,
              onTap: () => _openThread(t),
            ),
            const SizedBox(height: 12),
          ],
          if (finished.isNotEmpty) ...[
            _sectionLabel(theme, 'Finished'),
            for (final t in finished) _TicketRow(
              ticket: t,
              unread: _unread[t.id] ?? 0,
              onTap: () => _openThread(t),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      );
}

class _TicketRow extends StatelessWidget {
  final SupportTicket ticket;
  final int unread;
  final VoidCallback onTap;

  const _TicketRow({
    required this.ticket,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ticket;
    final finished = t.isFinished;
    final when = t.lastMessageAt ?? t.createdAt;

    return Opacity(
      opacity: finished ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.primaryColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      finished ? Icons.check_rounded : Icons.support_agent,
                      size: 21,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                unread > 0 ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (t.reference != null) t.reference!,
                            _statusLabel(t.status),
                            _when(when),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Open';
      case 'pending':
        return 'Waiting on support';
      case 'resolved':
        return 'Finished';
      case 'closed':
        return 'Finished';
      default:
        return status;
    }
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(d);
  }
}
