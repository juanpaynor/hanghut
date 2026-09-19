import 'package:flutter/material.dart';

import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/support/models/support_models.dart';
import 'package:bitemates/features/support/screens/support_thread_screen.dart';
import 'package:bitemates/features/support/services/support_service.dart';

/// The single way into support from anywhere in the app.
///
/// Resumes the most recent conversation that can still be replied to, rather
/// than opening a second thread every time someone taps "Contact support" —
/// two half-answered threads about the same problem is the classic helpdesk
/// failure and it costs an agent real time to untangle.
///
/// Closed threads are never resumed: replying to one is refused by RLS, so the
/// thread screen swaps its composer for "Start a new conversation", which comes
/// back here.
class SupportEntry {
  /// [category] and [subject] pre-fill the composer from wherever the user was.
  /// [openedFromPath] is provenance for the agent console — a stable slug such
  /// as `app/ticket/<id>`, never a Flutter route name (team_comms #316 Q3).
  static Future<void> open(
    BuildContext context, {
    SupportCategory category = SupportCategory.other,
    String? subject,
    String? openedFromPath,
  }) async {
    final service = SupportService();

    SupportTicket? existing;
    try {
      existing = await service.latestOpenTicket();
    } catch (_) {
      // A failed lookup should not block someone from reaching support; worst
      // case they open a second thread, which an agent can merge.
      existing = null;
    }
    if (!context.mounted) return;

    if (existing != null) {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => SupportThreadScreen(
            ticketId: existing!.id,
            initialTicket: existing,
          ),
        ),
      );
      // The thread screen returns 'new' when the user taps through from a
      // closed conversation.
      if (result != 'new' || !context.mounted) return;
    }

    await composeNew(
      context,
      category: category,
      subject: subject,
      openedFromPath: openedFromPath,
    );
  }

  /// Opens the new-ticket sheet and, on send, the resulting thread. Public so
  /// the support inbox can offer "New conversation" without going through the
  /// resume logic in [open].
  static Future<void> composeNew(
    BuildContext context, {
    SupportCategory category = SupportCategory.other,
    String? subject,
    String? openedFromPath,
  }) async {
    final ticket = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewTicketSheet(
        initialCategory: category,
        subject: subject,
        openedFromPath: openedFromPath,
      ),
    );
    if (ticket == null || !context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SupportThreadScreen(ticketId: ticket.id, initialTicket: ticket),
      ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  final SupportCategory initialCategory;
  final String? subject;
  final String? openedFromPath;

  const _NewTicketSheet({
    required this.initialCategory,
    this.subject,
    this.openedFromPath,
  });

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _body = TextEditingController();
  late SupportCategory _category = widget.initialCategory;
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _body.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final ticket = await SupportService().openTicket(
        body: text,
        category: _category,
        subject: widget.subject,
        openedFromPath: widget.openedFromPath,
      );
      if (mounted) Navigator.pop(context, ticket);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Could not start that conversation');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.support_agent, color: theme.primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Message support',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'We usually reply within a day. You can close the app — we will '
              'notify you when support answers.',
              style: TextStyle(
                  fontSize: 13.5, color: theme.textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 16),

            // Category is the routing axis inside support; it decides which
            // queue an agent sees this in, so it is worth one tap.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SupportCategory.values.map((c) {
                final selected = c == _category;
                return ChoiceChip(
                  label: Text(c.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _body,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'What do you need help with?',
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
