import 'package:flutter/material.dart';
import 'package:bitemates/core/services/report_service.dart';

/// Bottom sheet for reporting users, posts, comments, or tables.
/// Usage: ReportModal.show(context, targetType: 'user', targetId: userId);
class ReportModal extends StatefulWidget {
  final String targetType; // 'user', 'post', 'comment', 'table'
  final String targetId;
  final String? targetName; // Optional: display name for context

  const ReportModal({
    super.key,
    required this.targetType,
    required this.targetId,
    this.targetName,
  });

  /// Convenience method to show the modal
  static Future<void> show(
    BuildContext context, {
    required String targetType,
    required String targetId,
    String? targetName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportModal(
        targetType: targetType,
        targetId: targetId,
        targetName: targetName,
      ),
    );
  }

  @override
  State<ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<ReportModal> {
  String? _selectedReason;
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  bool _showDescription = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;

    setState(() => _isSubmitting = true);

    final success = await ReportService().submitReport(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reasonCategory: _selectedReason!,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      metadata: {
        'target_name': widget.targetName,
      },
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Report submitted. We\'ll review it shortly.'
                : 'Failed to submit report. Please try again.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  String get _targetLabel {
    switch (widget.targetType) {
      case 'user':
        return widget.targetName ?? 'this user';
      case 'post':
        return 'this post';
      case 'comment':
        return 'this comment';
      case 'table':
        return 'this hangout';
      default:
        return 'this content';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: Colors.red, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Report',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Why are you reporting $_targetLabel?',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Reason Categories
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    ...ReportService.reasonCategories.map((category) {
                      final isSelected = _selectedReason == category['key'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedReason = category['key'];
                              _showDescription = true;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                      ? Colors.red.withOpacity(0.15)
                                      : Colors.red.withOpacity(0.08))
                                  : (isDark
                                      ? Colors.grey[850]
                                      : Colors.grey[50]),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.red.withOpacity(0.5)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  category['icon']!,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        category['label']!,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? Colors.red : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        category['desc']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, color: Colors.red, size: 22),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    // Additional Details
                    if (_showDescription) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Additional details (optional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: 'Tell us more about what happened...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Submit Button
              Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  top: 8,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _selectedReason != null && !_isSubmitting
                        ? _submit
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
