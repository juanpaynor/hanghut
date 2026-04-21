import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/core/services/report_service.dart';

class ReportModal extends StatefulWidget {
  final String entityType; // 'user', 'table', 'message'
  final String entityId;
  final Map<String, dynamic>? metadata;

  const ReportModal({
    super.key,
    required this.entityType,
    required this.entityId,
    this.metadata,
  });

  @override
  State<ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<ReportModal> {
  final _reportService = ReportService();
  final _descriptionController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;

  // Categories based on Entity Type
  List<String> get _reasons {
    switch (widget.entityType) {
      case 'user':
        return [
          'Harassment / Bullying',
          'Fake Profile / Impersonation',
          'Inappropriate Content',
          'Spam / Scam',
          'Other',
        ];
      case 'table':
        return [
          'Misleading / Fake Event',
          'Dangerous / Illegal Activity',
          'Spam / Promotional',
          'Nudity / Sexual Content',
          'Other',
        ];
      case 'message':
        return [
          'Hate Speech',
          'Threats / Violence',
          'Unwanted Sexual Advances',
          'Spam',
          'Other',
        ];
      default:
        return ['Other'];
    }
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _reportService.submitReport(
        targetType: widget.entityType,
        targetId: widget.entityId,
        reasonCategory: _selectedReason!,
        description: _descriptionController.text.trim(),
        metadata: widget.metadata,
      );

      if (mounted) {
        Navigator.pop(context); // Close modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you for keeping us safe.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, error: e, fallbackMessage: 'Failed to submit report');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Report ${widget.entityType[0].toUpperCase()}${widget.entityType.substring(1)}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _selectedReason,
                hint: const Text('Select a reason'),
                items: _reasons.map((reason) {
                  return DropdownMenuItem(value: reason, child: Text(reason));
                }).toList(),
                onChanged: (value) => setState(() => _selectedReason = value),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Material(
                color: _isSubmitting || _selectedReason == null
                    ? Colors.redAccent.withOpacity(0.4)
                    : Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _isSubmitting || _selectedReason == null ? null : _submit,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    alignment: Alignment.center,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Submit Report',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
