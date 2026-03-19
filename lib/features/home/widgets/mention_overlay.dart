import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/social_service.dart';

/// A floating overlay that appears when the user types `@` in a text field.
/// Shows search results and inserts the selected username back into the text.
class MentionOverlay extends StatefulWidget {
  final String query;
  final Function(Map<String, dynamic> user) onUserSelected;

  const MentionOverlay({
    super.key,
    required this.query,
    required this.onUserSelected,
  });

  @override
  State<MentionOverlay> createState() => _MentionOverlayState();
}

class _MentionOverlayState extends State<MentionOverlay> {
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search(widget.query);
  }

  @override
  void didUpdateWidget(MentionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _search(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final results = await SocialService().searchUsers(query, limit: 5);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_results.isEmpty && !_isLoading) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemBuilder: (context, index) {
                final user = _results[index];
                final avatarUrl = user['avatar_url'];

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: avatarUrl != null &&
                            avatarUrl.toString().isNotEmpty
                        ? CachedNetworkImageProvider(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.toString().isEmpty
                        ? const Icon(Icons.person, size: 16, color: Colors.grey)
                        : null,
                  ),
                  title: Text(
                    user['display_name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: user['username'] != null
                      ? Text(
                          '@${user['username']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        )
                      : null,
                  onTap: () => widget.onUserSelected(user),
                );
              },
            ),
    );
  }
}
