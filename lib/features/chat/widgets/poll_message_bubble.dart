import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// Renders an in-chat poll card. Fetches vote data live from Supabase.
class PollMessageBubble extends StatefulWidget {
  final String pollId;
  final bool isMe;

  const PollMessageBubble({
    super.key,
    required this.pollId,
    required this.isMe,
  });

  @override
  State<PollMessageBubble> createState() => _PollMessageBubbleState();
}

class _PollMessageBubbleState extends State<PollMessageBubble> {
  Map<String, dynamic>? _poll;
  List<Map<String, dynamic>> _votes = [];
  String? _myVoteOptionId;
  bool _isLoading = true;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _loadPoll();
  }

  Future<void> _loadPoll() async {
    try {
      final pollData = await SupabaseConfig.client
          .from('chat_polls')
          .select('*')
          .eq('id', widget.pollId)
          .maybeSingle();

      if (pollData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final votes = await SupabaseConfig.client
          .from('chat_poll_votes')
          .select('option_id, user_id')
          .eq('poll_id', widget.pollId);

      final voteList = List<Map<String, dynamic>>.from(votes);
      final currentUserId = SupabaseConfig.client.auth.currentUser!.id;
      final myVote = voteList.where((v) => v['user_id'] == currentUserId).firstOrNull;

      if (mounted) {
        setState(() {
          _poll = Map<String, dynamic>.from(pollData);
          _votes = voteList;
          _myVoteOptionId = myVote?['option_id'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ PollBubble: Error loading poll $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _vote(String optionId) async {
    if (_isVoting || _poll?['is_closed'] == true) return;
    final isSameOption = _myVoteOptionId == optionId;

    // Optimistic update
    final currentUserId = SupabaseConfig.client.auth.currentUser!.id;
    setState(() {
      _isVoting = true;
      if (isSameOption) {
        // Remove vote
        _votes.removeWhere((v) => v['user_id'] == currentUserId);
        _myVoteOptionId = null;
      } else {
        // Upsert vote
        _votes.removeWhere((v) => v['user_id'] == currentUserId);
        _votes.add({'option_id': optionId, 'user_id': currentUserId});
        _myVoteOptionId = optionId;
      }
    });

    try {
      final currentUserId = SupabaseConfig.client.auth.currentUser!.id;
      if (isSameOption) {
        await SupabaseConfig.client
            .from('chat_poll_votes')
            .delete()
            .eq('poll_id', widget.pollId)
            .eq('user_id', currentUserId);
      } else {
        await SupabaseConfig.client.from('chat_poll_votes').upsert({
          'poll_id': widget.pollId,
          'user_id': currentUserId,
          'option_id': optionId,
        }, onConflict: 'poll_id,user_id');
      }
    } catch (e) {
      debugPrint('❌ PollBubble: Vote failed $e');
      // Revert by reloading
      _loadPoll();
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = widget.isMe
        ? Theme.of(context).primaryColor
        : (isDark ? Colors.grey[800]! : Colors.grey[100]!);
    final textColor = widget.isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);

    if (_isLoading) {
      return Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_poll == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('Poll no longer available', style: TextStyle(color: textColor, fontSize: 13)),
      );
    }

    final options = List<Map<String, dynamic>>.from(_poll!['options'] as List);
    final totalVotes = _votes.length;
    final isClosed = _poll!['is_closed'] == true;
    final expiresAt = _poll!['expires_at'] != null
        ? DateTime.parse(_poll!['expires_at']).toLocal()
        : null;
    final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);
    final isInactive = isClosed || isExpired;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isMe
              ? Colors.white.withOpacity(0.2)
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 16, color: textColor.withOpacity(0.7)),
              const SizedBox(width: 6),
              Text(
                isInactive ? 'POLL CLOSED' : 'POLL',
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Question
          Text(
            _poll!['question'] as String,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Options
          ...options.map((opt) {
            final optId = opt['id'] as String;
            final optText = opt['text'] as String;
            final voteCount = _votes.where((v) => v['option_id'] == optId).length;
            final percent = totalVotes == 0 ? 0.0 : voteCount / totalVotes;
            final isSelected = _myVoteOptionId == optId;

            return GestureDetector(
              onTap: isInactive ? null : () => _vote(optId),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    // Background vote bar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: widget.isMe
                            ? Colors.white.withOpacity(0.15)
                            : (isDark ? Colors.grey[700] : Colors.grey[200]),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      height: 38,
                      width: 232 * percent,  // 260 - 14 - 14 padding
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected
                            ? (widget.isMe
                                ? Colors.white.withOpacity(0.35)
                                : Theme.of(context).primaryColor.withOpacity(0.25))
                            : (widget.isMe
                                ? Colors.white.withOpacity(0.15)
                                : (isDark ? Colors.grey[700] : Colors.grey[200])),
                      ),
                    ),
                    // Text and percentage row
                    SizedBox(
                      height: 38,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: widget.isMe
                                      ? Colors.white
                                      : Theme.of(context).primaryColor,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                optText,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              totalVotes > 0 ? '${(percent * 100).round()}%' : '',
                              style: TextStyle(
                                color: textColor.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          // Vote count footer
          Text(
            '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}${isInactive ? ' • Closed' : ''}',
            style: TextStyle(
              color: textColor.withOpacity(0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
