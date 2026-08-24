import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bitemates/core/services/event_analytics_service.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';
import 'package:bitemates/features/sharing/services/share_sender.dart';

/// Phase 1 share-to-chat with multi-select: pick one or more recent chats and
/// send an entity into all of them at once. Sending is headless (via
/// [ShareSender]) — the chats are not opened. Also offers an "outside HangHut"
/// fallback to the system share sheet.
class ShareToChatSheet extends StatefulWidget {
  final SharePayload payload;

  /// The context that opened the sheet — used to show the confirmation snackbar
  /// after the sheet pops (the sheet's own context is gone by then).
  final BuildContext hostContext;

  const ShareToChatSheet({
    super.key,
    required this.payload,
    required this.hostContext,
  });

  static Future<void> show(BuildContext context, SharePayload payload) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareToChatSheet(payload: payload, hostContext: context),
    );
  }

  @override
  State<ShareToChatSheet> createState() => _ShareToChatSheetState();
}

class _ShareToChatSheetState extends State<ShareToChatSheet> {
  final _service = ChatListService();
  final _captionController = TextEditingController();
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  bool _sending = false;
  String _query = '';

  /// Keys ("chat_type:chat_id") of the chats currently selected to send into.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chats = await _service.fetchActiveChats(limit: 30);
    if (!mounted) return;
    setState(() {
      _chats = chats;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return _chats;
    final q = _query.toLowerCase();
    return _chats
        .where((c) => (c['title'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  String _keyFor(Map<String, dynamic> chat) =>
      '${chat['chat_type'] ?? 'table'}:${chat['chat_id']}';

  String _channelIdFor(Map<String, dynamic> chat) {
    final type = chat['chat_type'];
    final id = chat['chat_id'];
    if (type == 'trip') {
      final bucket = (chat['metadata'] as Map?)?['bucket_id'] as String?;
      return bucket ?? 'trip_$id';
    }
    if (type == 'dm') return 'direct_$id';
    if (type == 'group') return 'group_$id';
    return 'table_$id';
  }

  void _toggle(Map<String, dynamic> chat) {
    if (_sending) return;
    final key = _keyFor(chat);
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  Future<void> _sendToSelected() async {
    if (_sending || _selected.isEmpty) return;
    setState(() => _sending = true);

    final targets = _chats
        .where((c) => _selected.contains(_keyFor(c)))
        .map((c) => ShareTarget(
              chatType: (c['chat_type'] ?? 'table').toString(),
              tableId: c['chat_id'].toString(),
              channelId: _channelIdFor(c),
              title: (c['title'] ?? 'Chat').toString(),
            ))
        .toList();

    final payload = widget.payload.withNote(_captionController.text);
    final result = await ShareSender.send(targets, payload);
    for (var i = 0; i < result.sent; i++) {
      EventAnalyticsService.instance.logShare(widget.payload.id);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    _showSnack(_confirmationText(result, targets));
  }

  String _confirmationText(
    ({int sent, int failed}) result,
    List<ShareTarget> targets,
  ) {
    if (result.sent == 0) return "Couldn't send — please try again";
    final base = result.sent == 1
        ? 'Shared to ${targets.first.title}'
        : 'Shared to ${result.sent} chats';
    return result.failed > 0 ? '$base · ${result.failed} failed' : base;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(widget.hostContext)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  void _shareExternally() {
    if (_sending) return;
    Navigator.of(context).pop();
    EventAnalyticsService.instance.logShare(widget.payload.id);
    SharePlus.instance.share(ShareParams(text: widget.payload.shareText()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1B1B24) : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                Text(
                  'Share to',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _shareExternally,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Outside HangHut'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search chats',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor:
                    isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildList(isDark)),
          _buildSendBar(isDark),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No chats yet' : 'No chats match "$_query"',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final chat = items[i];
        final title = (chat['title'] ?? 'Chat').toString();
        final subtitle = (chat['subtitle'] ?? '').toString();
        final imageUrl = chat['image_url'] as String?;
        final selected = _selected.contains(_keyFor(chat));
        final accent = Theme.of(context).primaryColor;
        return ListTile(
          onTap: () => _toggle(chat),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: accent.withOpacity(0.15),
            backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                ? CachedNetworkImageProvider(imageUrl)
                : null,
            child: (imageUrl == null || imageUrl.isEmpty)
                ? Icon(Icons.person, color: accent)
                : null,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _SelectDot(selected: selected, color: accent),
        );
      },
    );
  }

  Widget _buildSendBar(bool isDark) {
    final count = _selected.length;
    final enabled = count > 0 && !_sending;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: count == 0
          ? const SizedBox(width: double.infinity)
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _captionController,
                      enabled: !_sending,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Add a message…',
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.04),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: ElevatedButton(
                    onPressed: enabled ? _sendToSelected : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            count == 1 ? 'Send' : 'Send to $count',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A trailing check/empty circle indicating a chat's selection state.
class _SelectDot extends StatelessWidget {
  final bool selected;
  final Color color;

  const _SelectDot({required this.selected, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected ? color : Colors.grey.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}
