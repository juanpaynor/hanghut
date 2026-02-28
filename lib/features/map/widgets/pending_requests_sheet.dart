import 'package:flutter/material.dart';
import 'package:bitemates/core/services/table_member_service.dart';

class PendingRequestsSheet extends StatefulWidget {
  final String tableId;
  final String tableTitle;

  const PendingRequestsSheet({
    super.key,
    required this.tableId,
    required this.tableTitle,
  });

  @override
  State<PendingRequestsSheet> createState() => _PendingRequestsSheetState();
}

class _PendingRequestsSheetState extends State<PendingRequestsSheet> {
  final _memberService = TableMemberService();
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  Future<void> _loadPendingRequests() async {
    final requests = await _memberService.getPendingRequests(widget.tableId);
    if (mounted) {
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(String userId, int index) async {
    setState(() => _requests[index]['_loading'] = true);
    final result = await _memberService.approveRequest(widget.tableId, userId);
    if (mounted) {
      if (result['success'] == true) {
        setState(() => _requests.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request approved!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _requests[index]['_loading'] = false);
      }
    }
  }

  Future<void> _decline(String userId, int index) async {
    setState(() => _requests[index]['_loading'] = true);
    final result = await _memberService.rejectRequest(widget.tableId, userId);
    if (mounted) {
      if (result['success'] == true) {
        setState(() => _requests.removeAt(index));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request declined')));
      } else {
        setState(() => _requests[index]['_loading'] = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.person_add, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Join Requests',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (_requests.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_requests.length}',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 20),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.black),
            )
          else if (_requests.isEmpty)
            _buildEmptyState()
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _requests.length,
                itemBuilder: (context, index) =>
                    _buildRequestCard(_requests[index], index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No pending requests',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New requests will appear here',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, int index) {
    final user = request['users'] as Map<String, dynamic>?;
    final name = user?['display_name'] ?? 'Unknown';
    final bio = user?['bio'] as String?;
    final trustScore = user?['trust_score'] as int? ?? 50;
    final userId = request['user_id'] as String;
    final isActionLoading = request['_loading'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[300],
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bio,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.shield, size: 14, color: Colors.blue[400]),
                    const SizedBox(width: 4),
                    Text(
                      'Trust: $trustScore',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[400],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          if (isActionLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decline
                GestureDetector(
                  onTap: () => _decline(userId, index),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.close, color: Colors.red[400], size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                // Approve
                GestureDetector(
                  onTap: () => _approve(userId, index),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.check,
                      color: Colors.green[600],
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
