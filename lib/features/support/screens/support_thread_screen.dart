import 'dart:async';
import 'dart:io';

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/support/models/support_models.dart';
import 'package:bitemates/features/support/services/support_service.dart';

/// One support conversation.
///
/// Bodies come from web's `support_messages` on every load and on every Ably
/// signal — nothing is cached across sessions. That is deliberate: a retraction
/// EMPTIES the body in Postgres rather than flagging it (team_comms #313),
/// because the feature exists for someone who pasted a live key. A local copy
/// would survive the retraction and defeat the point.
class SupportThreadScreen extends StatefulWidget {
  final String ticketId;

  /// Passed when we already have it, to avoid a blank header on first frame.
  final SupportTicket? initialTicket;

  const SupportThreadScreen({
    super.key,
    required this.ticketId,
    this.initialTicket,
  });

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen>
    with WidgetsBindingObserver {
  final _service = SupportService();
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  SupportTicket? _ticket;
  List<SupportMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  StreamSubscription<void>? _signals;
  StreamSubscription<ably.ConnectionStateChange>? _connection;

  /// Set the moment Ably drops, cleared by the catch-up refetch on the way
  /// back. Without this a reconnect would refetch on every state change,
  /// including the connected->connected churn Ably emits on its own.
  bool _wasDisconnected = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listen();
    _watchConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signals?.cancel();
    _connection?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Ably carries only `{ticketId}`, so every signal means "refetch", never
  /// "here is a message". Cheap, and it is what makes a forged publish inert.
  void _listen() {
    _signals = _service.watchTicket(widget.ticketId).listen(
          (_) => _load(silent: true),
          onError: (_) {},
        );
  }

  /// Ably is a LIVE transport, not a log. A connection that has been suspended
  /// — which is what backgrounding the app does within ~2 minutes — resumes
  /// without replaying what was published while it was gone, so an agent reply
  /// that lands in that window is never signalled and the thread sits stale
  /// until the screen is destroyed and rebuilt. That is exactly the "I had to
  /// close and reopen it" symptom.
  ///
  /// So the signal is treated as the fast path and never as the only one: every
  /// return to the foreground refetches. chat_screen has carried this since the
  /// same bug bit DMs; support is chat and needs it for the same reason.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  /// The other half: a network blip with the app still in front. Ably
  /// reconnects itself, but the messages published during the gap are gone, so
  /// the reconnect is the cue to refetch.
  Future<void> _watchConnection() async {
    // Awaited: the stream only exists once the Ably client does, and initState
    // runs before init() has finished. Reading it synchronously would hand back
    // null and this whole path would quietly never run.
    final states = await _service.connectionStates();
    if (states == null || !mounted) return;
    _connection = states.listen((change) {
      if (!mounted) return;
      if (change.current == ably.ConnectionState.connected) {
        if (_wasDisconnected) {
          _wasDisconnected = false;
          _load(silent: true);
        }
      } else if (change.current == ably.ConnectionState.disconnected ||
          change.current == ably.ConnectionState.suspended ||
          change.current == ably.ConnectionState.closed) {
        _wasDisconnected = true;
      }
    }, onError: (_) {});
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getTicket(widget.ticketId),
        _service.fetchThread(widget.ticketId),
      ]);
      if (!mounted) return;
      setState(() {
        _ticket = results[0] as SupportTicket? ?? _ticket;
        _messages = results[1] as List<SupportMessage>;
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
      // After every successful load, not just the first: a signal-driven
      // refetch means an agent reply just landed while the user is looking at
      // it, and that is exactly the moment the badge should clear.
      _service.markRead(widget.ticketId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorHandler.getUserMessage(e,
            fallback: 'Could not load this conversation');
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await _service.sendMessage(ticketId: widget.ticketId, body: text);
      _composer.clear();
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Could not send that message');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Retraction is offered only on the requester's own, still-standing
  /// messages. Agents cannot retract at all, so there is no branch for it.
  Future<void> _confirmRetract(SupportMessage m) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (m.isRetracted || m.isFromAgent || m.isSystem) return;
    if (m.senderUserId != null && m.senderUserId != uid) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove message'),
              subtitle: const Text(
                'The text is deleted permanently. Support will see that a '
                'message was removed.',
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await _service.retractMessage(
        messageId: m.id,
        ticketId: widget.ticketId,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Could not remove that message');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _ticket;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('HangHut Support',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (t != null)
              Text(
                [
                  if (t.reference != null) t.reference!,
                  _statusLabel(t.status),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(theme)),
          if (t != null)
            t.isFinished ? _buildClosedFooter(theme) : _buildComposer(theme),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        itemCount: _messages.length,
        itemBuilder: (_, i) => _bubble(theme, _messages[i]),
      ),
    );
  }

  Widget _bubble(ThemeData theme, SupportMessage m) {
    if (m.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            m.body,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, color: theme.textTheme.bodySmall?.color),
          ),
        ),
      );
    }

    final mine = !m.isFromAgent;
    final primary = theme.primaryColor;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? () => _confirmRetract(m) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: m.isRetracted
                ? theme.dividerColor.withValues(alpha: 0.18)
                : mine
                    ? primary
                    : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: mine || m.isRetracted
                ? null
                : Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine && !m.isRetracted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.support_agent, size: 14, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        'HangHut Support',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),

              // NEVER render `body` on a retracted message — it is empty in
              // Postgres anyway, but the placeholder is what tells the user the
              // removal actually took effect.
              if (m.isRetracted)
                Text(
                  'Message removed',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                )
              else ...[
                // Attachments carry the file name as the message body, so the
                // text would just repeat the caption under the image.
                for (final a in m.attachments)
                  _AttachmentView(attachment: a, onDark: mine),
                if (m.attachments.isEmpty)
                  Text(
                    m.body,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      color:
                          mine ? Colors.white : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shown for any finished thread. Closed is RLS-final (a send would be
  /// refused with no usable reason, #316); resolved is UI-final by our own
  /// choice — either way the composer is replaced BEFORE the user can type.
  Widget _buildClosedFooter(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 15, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'This conversation is finished.',
                    style: TextStyle(
                        fontSize: 13, color: theme.textTheme.bodySmall?.color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, 'new'),
                child: const Text('Start a new conversation'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _sending ? null : _attach,
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Attach a photo',
              color: theme.textTheme.bodySmall?.color,
            ),
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write a message…',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              color: theme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attach() async {
    if (_sending) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Kept well inside the bucket's 10 MB ceiling. A modern phone photo is
        // routinely 8-12 MB straight off the camera, so uploading the original
        // would fail at the bucket for a meaningful share of users — and a
        // support screenshot needs legibility, not megapixels.
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _sending = true);
      final name = picked.name.isNotEmpty ? picked.name : 'image.jpg';
      final mime = name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : name.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : name.toLowerCase().endsWith('.gif')
                  ? 'image/gif'
                  : 'image/jpeg';

      await _service.sendAttachment(
        ticketId: widget.ticketId,
        file: File(picked.path),
        fileName: name,
        mimeType: mime,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Could not attach that file');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Open';
      case 'pending':
        return 'Waiting on support';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }
}

/// One attachment inside a bubble.
///
/// The bucket is PRIVATE, so there is no durable URL to render — each view
/// signs a fresh one. Signing happens per widget rather than per thread load
/// so that a long-lived screen doesn't hold a pile of URLs that expire while
/// the user is reading.
class _AttachmentView extends StatefulWidget {
  final SupportAttachment attachment;
  final bool onDark;

  const _AttachmentView({required this.attachment, required this.onDark});

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  String? _url;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sign();
  }

  Future<void> _sign() async {
    final url = await SupportService().signedUrl(widget.attachment.storagePath);
    if (!mounted) return;
    setState(() {
      _url = url;
      _failed = url == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    final theme = Theme.of(context);
    final onDark = widget.onDark;

    // Non-images (PDFs) render as a labelled chip rather than a preview. Only
    // an agent can send one today — our picker is images-only — so this is the
    // graceful path, not the main one.
    if (!a.isImage) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: onDark ? Colors.white24 : theme.dividerColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          a.fileName,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: onDark ? Colors.white : theme.textTheme.bodyLarge?.color,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260, minWidth: 140),
        child: _failed
            ? Container(
                height: 100,
                alignment: Alignment.center,
                color: theme.dividerColor.withValues(alpha: 0.25),
                child: const Text('Image unavailable',
                    style: TextStyle(fontSize: 12.5)),
              )
            : _url == null
                ? Container(
                    height: 140,
                    color: theme.dividerColor.withValues(alpha: 0.25),
                  )
                : CachedNetworkImage(
                    imageUrl: _url!,
                    fit: BoxFit.cover,
                    // Signed URLs expire, so a cached entry keyed on the URL
                    // would be refetched under a new key each time anyway.
                    placeholder: (_, __) => Container(
                      height: 140,
                      color: theme.dividerColor.withValues(alpha: 0.25),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 100,
                      alignment: Alignment.center,
                      color: theme.dividerColor.withValues(alpha: 0.25),
                      child: const Text('Image unavailable',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
      ),
    );
  }
}
