import 'package:flutter/material.dart';
import 'package:bitemates/core/services/social_service.dart';

class EditPostModal extends StatefulWidget {
  final Map<String, dynamic> post;

  const EditPostModal({super.key, required this.post});

  @override
  State<EditPostModal> createState() => _EditPostModalState();
}

class _EditPostModalState extends State<EditPostModal> {
  late TextEditingController _contentController;
  bool _isSubmitting = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.post['content'] ?? '',
    );
    _contentController.addListener(_onChanged);
  }

  void _onChanged() {
    final changed = _contentController.text != (widget.post['content'] ?? '');
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newContent = _contentController.text.trim();
    if (newContent.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post cannot be empty')));
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await SocialService().editPost(
      postId: widget.post['id'],
      content: newContent,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (result != null) {
        Navigator.pop(context, result); // Return updated post
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show existing images/gif as read-only preview
    final imageUrls = widget.post['image_urls'] as List?;
    final gifUrl = widget.post['gif_url'] as String?;
    final hasMedia =
        (imageUrls != null && imageUrls.isNotEmpty) ||
        (gifUrl != null && gifUrl.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Edit Post',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _hasChanges && !_isSubmitting ? _save : null,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _hasChanges
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey[400],
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              // Content editor
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        minLines: 4,
                        autofocus: true,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                        decoration: InputDecoration(
                          hintText: "What's on your mind?",
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),

                      // Show existing media as read-only
                      if (hasMedia) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.photo_library,
                                size: 20,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  gifUrl != null
                                      ? 'GIF attached (cannot be changed)'
                                      : '${imageUrls!.length} image${imageUrls.length > 1 ? 's' : ''} attached (cannot be changed)',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Event indicator
                      if (widget.post['event_id'] != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event,
                                size: 20,
                                color: Colors.blue[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Event attached (cannot be changed)',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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
