import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';
import 'package:bitemates/features/sharing/services/share_sender.dart';

/// Forward an existing chat message into one or more other chats. Multi-select,
/// headless send via [ShareSender.forward] (the message is not opened). Mirrors
/// the share-to-chat sheet, minus caption/external options — a forward carries
/// the original content verbatim.
class ForwardMessageSheet extends StatefulWidget {
  /// The raw message content and its content-type (text/image/gif/share/…).
  final String content;
  final String contentType;

  /// Short human label for the confirmation snackbar ("Forwarded a photo").
  final String kindLabel;

  final BuildContext hostContext;

  const ForwardMessageSheet({
    super.key,
    required this.content,
    required this.contentType,
    required this.kindLabel,
    required this.hostContext,
  });

  static Future<void> show(
    BuildContext context, {
    required String content,
    required String contentType,
    required String kindLabel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardMessageSheet(
        content: content,
        contentType: contentType,
        kindLabel: kindLabel,
        hostContext: context,
      ),
    );
  }

  @override
  State<ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<ForwardMessageSheet> {
  final _service = ChatListService();
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  bool _sending = false;
  String _query = '';
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
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
      _selected.contains(key) ? _selected.remove(key) : _selected.add(key);
    });
  }

  Future<void> _send() async {
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

    final result = await ShareSender.forward(
      targets,
      content: widget.content,
      contentType: widget.contentType,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    final msg = result.sent == 0
        ? "Couldn't forward — please try again"
        : result.sent == 1
            ? 'Forwarded ${widget.kindLabel} to ${targets.first.title}'
            : 'Forwarded ${widget.kindLabel} to ${result.sent} chats';
    ScaffoldMessenger.of(widget.hostContext)
        .showSnackBar(SnackBar(content: Text(msg)));
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
                  'Forward to',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
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
          _buildSendBar(),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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

  Widget _buildSendBar() {
    final count = _selected.length;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: count == 0
          ? const SizedBox(width: double.infinity)
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _send,
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            count == 1 ? 'Forward' : 'Forward to $count',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ),
            ),
    );
  }
}

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
