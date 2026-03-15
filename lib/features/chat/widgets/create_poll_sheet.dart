import 'package:flutter/material.dart';

/// Bottom sheet for creating a poll in a group chat.
/// Returns a Map with 'question' and 'options' keys when user taps Send.
class CreatePollSheet extends StatefulWidget {
  const CreatePollSheet({super.key});

  @override
  State<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<CreatePollSheet> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool get _isValid {
    final questionFilled = _questionController.text.trim().isNotEmpty;
    final atLeastTwoOptions = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length >= 2;
    return questionFilled && atLeastTwoOptions;
  }

  void _addOption() {
    if (_optionControllers.length >= 4) return;
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _submit() {
    if (!_isValid) return;
    final options = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((e) => {
              'id': String.fromCharCode(97 + e.key), // 'a', 'b', 'c', 'd'
              'text': e.value.text.trim(),
            })
        .toList();

    Navigator.of(context).pop({
      'question': _questionController.text.trim(),
      'options': options,
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Row(
              children: [
                Icon(Icons.poll_outlined, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Create a Poll',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Question field
            Text(
              'Question',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _questionController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              maxLength: 120,
              decoration: InputDecoration(
                hintText: 'Ask something...',
                hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                counterStyle: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 16),
            // Options
            Text(
              'Options  (${_optionControllers.length}/4)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(_optionControllers.length, (i) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[i],
                        onChanged: (_) => setState(() {}),
                        maxLength: 60,
                        decoration: InputDecoration(
                          hintText: 'Option ${i + 1}',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    if (_optionControllers.length > 2) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _removeOption(i),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            // Add option button
            if (_optionControllers.length < 4)
              GestureDetector(
                onTap: _addOption,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.4),
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 16, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'Add Option',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            // Send button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValid ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Launch Poll',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
