import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';

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
    // Some organizers already type a trailing "*" in their label — don't add a
    // second one, which looked like "... * *".
    final showAsterisk = required && !label.trimRight().endsWith('*');

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
                height: 1.3,
              ),
              children: [
                if (showAsterisk)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
        final current = widget.answers[id] as String?;
        return Column(
          children: options
              .map((opt) => _ChoiceCard(
                    label: opt,
                    selected: current == opt,
                    isMulti: false,
                    onTap: () => _update(id, opt),
                  ))
              .toList(),
        );

      case 'multi_choice':
        final options = _options(q);
        final selected =
            List<String>.from(widget.answers[id] as List? ?? []);
        return Column(
          children: options.map((opt) {
            final checked = selected.contains(opt);
            return _ChoiceCard(
              label: opt,
              selected: checked,
              isMulti: true,
              onTap: () {
                final updated = List<String>.from(selected);
                if (checked) {
                  updated.remove(opt);
                } else {
                  updated.add(opt);
                }
                _update(id, updated);
              },
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
          activeColor: AppTheme.primaryColor,
          controlAffinity: ListTileControlAffinity.leading,
        );

      default:
        return _textField(id, maxLines: 1);
    }
  }

  Widget _textField(String id, {int maxLines = 1, String? hint}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;
    return TextField(
      controller: _controllers[id],
      maxLines: maxLines,
      onChanged: (v) => _update(id, v),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.grey[400],
          fontSize: 14,
        ),
        filled: true,
        fillColor: fill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
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

/// A tappable card for a single/multi choice option — indigo highlight when
/// selected, with a radio (single) or check (multi) indicator.
class _ChoiceCard extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isMulti;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.label,
    required this.selected,
    required this.isMulti,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBorder =
        isDark ? Colors.white.withValues(alpha: 0.16) : Colors.grey.shade300;
    final unselectedText = isDark ? Colors.white : Colors.black87;
    final unselectedIndicator =
        isDark ? Colors.white38 : Colors.grey.shade400;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? primary : unselectedBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _indicator(primary, unselectedIndicator),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? primary : unselectedText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicator(Color primary, Color unselectedColor) {
    if (isMulti) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? primary : unselectedColor,
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : null,
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? primary : unselectedColor,
          width: selected ? 6 : 1.5,
        ),
      ),
    );
  }
}
