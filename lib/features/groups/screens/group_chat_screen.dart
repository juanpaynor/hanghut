import 'package:flutter/material.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';
import 'package:bitemates/features/groups/utils/group_cover_theme.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';

/// Full-screen group chat. The chat is the primary experience; group details
/// and activities live behind the ⓘ button (which opens [GroupDetailScreen]).
class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;
  final String? groupImageUrl;
  final String? iconEmoji;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.groupImageUrl,
    this.iconEmoji,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ChatListService _chatListService = ChatListService();
  bool _muted = false;
  bool _muteLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMuted();
  }

  Future<void> _loadMuted() async {
    final muted = await _chatListService.isChatMuted(widget.groupId);
    if (mounted) {
      setState(() {
        _muted = muted;
        _muteLoaded = true;
      });
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next); // optimistic
    final ok = await _chatListService.setChatMuted(widget.groupId, next);
    if (!mounted) return;
    if (!ok) {
      setState(() => _muted = !next); // revert
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Group muted' : 'Group unmuted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(groupId: widget.groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (widget.groupName == null || widget.groupName!.isEmpty)
        ? 'Group'
        : widget.groupName!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        title: InkWell(
          onTap: _openInfo,
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                        if (_muted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notifications_off,
                            size: 15,
                            color: Colors.grey[500],
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'Tap for group info',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_muteLoaded)
            IconButton(
              icon: Icon(
                _muted ? Icons.notifications_off : Icons.notifications_active,
              ),
              tooltip: _muted ? 'Unmute group' : 'Mute group',
              onPressed: _toggleMute,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Group info',
            onPressed: _openInfo,
          ),
        ],
      ),
      body: ChatScreen(
        channelId: 'group_${widget.groupId}',
        tableId: widget.groupId,
        tableTitle: name,
        chatType: 'group',
        embedded: true,
      ),
    );
  }

  Widget _avatar() {
    if (widget.groupImageUrl != null && widget.groupImageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(widget.groupImageUrl!),
      );
    }
    final cover = GroupCover.forGroup(category: null, seed: widget.groupId);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cover.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: (widget.iconEmoji != null && widget.iconEmoji!.isNotEmpty)
            ? Text(widget.iconEmoji!, style: const TextStyle(fontSize: 18))
            : Icon(Icons.groups, color: cover.accent, size: 20),
      ),
    );
  }
}
