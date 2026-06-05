import 'package:flutter/material.dart';

class RegistrationQuestionsForm extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final Map<String, dynamic> answers;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const RegistrationQuestionsForm({
    super.key,
    required this.questions,
    required this.answers,
    required this.onChanged,
  });

  /// Returns null if valid, or an error message for the first unanswered required question.
  static String? validate(
    List<Map<String, dynamic>> questions,
    Map<String, dynamic> answers,
  ) {
    for (final q in questions) {
      if (q['is_required'] != true) continue;
      final id = q['id'] as String;
      final answer = answers[id];
      final type = q['question_type'] as String;
      if (type == 'multi_choice') {
        if (answer == null || (answer as List).isEmpty) {
          return 'Please answer: ${q['label']}';
        }
      } else if (type == 'checkbox') {
        // checkbox required = must be checked
        if (answer != true) return 'Please accept: ${q['label']}';
      } else {
        if (answer == null || answer.toString().trim().isEmpty) {
          return 'Please answer: ${q['label']}';
        }
      }
    }
    return null;
  }

  @override
  State<RegistrationQuestionsForm> createState() =>
      _RegistrationQuestionsFormState();
}

class _RegistrationQuestionsFormState
    extends State<RegistrationQuestionsForm> {
  // Text controllers keyed by question_id
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final q in widget.questions) {
      final id = q['id'] as String;
      final type = q['question_type'] as String;
      if (_isTextField(type)) {
        _controllers[id] = TextEditingController(
          text: widget.answers[id]?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isTextField(String type) => [
        'short_text',
        'long_text',
        'social_profile',
        'url',
        'company',
      ].contains(type);

  void _update(String id, dynamic value) {
    final updated = Map<String, dynamic>.from(widget.answers);
    updated[id] = value;
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Registration Details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...widget.questions.map((q) => _buildQuestion(q)),
      ],
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q) {
    final id = q['id'] as String;
    final label = q['label'] as String;
    final type = q['question_type'] as String;
    final required = q['is_required'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _buildInput(id, type, q),
        ],
      ),
    );
  }

  Widget _buildInput(String id, String type, Map<String, dynamic> q) {
    switch (type) {
      case 'short_text':
      case 'company':
        return _textField(id, maxLines: 1);

      case 'long_text':
        return _textField(id, maxLines: 4);

      case 'url':
        return _textField(id, maxLines: 1, hint: 'https://');

      case 'social_profile':
        return _textField(
          id,
          maxLines: 1,
          hint: 'e.g. instagram.com/username or @handle',
        );

      case 'single_choice':
        final options = _options(q);
        return RadioGroup<String>(
          groupValue: widget.answers[id] as String?,
          onChanged: (v) => _update(id, v),
          child: Column(
            children: options.map((opt) => RadioListTile<String>(
              value: opt,
              title: Text(opt, style: const TextStyle(fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.deepPurple,
            )).toList(),
          ),
        );

      case 'multi_choice':
        final options = _options(q);
        final selected =
            List<String>.from(widget.answers[id] as List? ?? []);
        return Column(
          children: options.map((opt) {
            final checked = selected.contains(opt);
            return CheckboxListTile(
              value: checked,
              onChanged: (v) {
                final updated = List<String>.from(selected);
                if (v == true) {
                  updated.add(opt);
                } else {
                  updated.remove(opt);
                }
                _update(id, updated);
              },
              title: Text(opt, style: const TextStyle(fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.deepPurple,
              controlAffinity: ListTileControlAffinity.leading,
            );
          }).toList(),
        );

      case 'checkbox':
        return CheckboxListTile(
          value: widget.answers[id] == true,
          onChanged: (v) => _update(id, v ?? false),
          title: const Text(
            'I agree',
            style: TextStyle(fontSize: 14),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.deepPurple,
          controlAffinity: ListTileControlAffinity.leading,
        );

      default:
        return _textField(id, maxLines: 1);
    }
  }

  Widget _textField(String id, {int maxLines = 1, String? hint}) {
    return TextField(
      controller: _controllers[id],
      maxLines: maxLines,
      onChanged: (v) => _update(id, v),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.deepPurple),
        ),
      ),
    );
  }

  List<String> _options(Map<String, dynamic> q) {
    final raw = q['options'];
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }
}
