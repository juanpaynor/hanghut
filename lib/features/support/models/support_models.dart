/// Models for the async support system.
///
/// Message bodies live in web's `support_messages` — that table is the single
/// source of truth (the A2 contract, team_comms #305). The app reads and writes
/// it directly through RLS; nothing here is mirrored into our own `messages`
/// table, and the `chat_inbox` row is only a pointer.
library;

/// One message in a support thread.
class SupportMessage {
  final String id;
  final String ticketId;

  /// 'requester' | 'agent' | 'system'. Renamed from 'organizer' in #309 — do
  /// not reintroduce the old value, the CHECK constraints reject it.
  final String sender;

  /// Empty when [isRetracted]. The body is DESTROYED in Postgres on retraction,
  /// not flagged (#313), because the feature exists for someone who pasted a
  /// live key. Never render this when [isRetracted] is true.
  final String body;

  /// Staff-only note. RLS already hides these from a requester, so this should
  /// never arrive true on a user's device — filtered again in the reader as
  /// belt and braces, per #309.
  final bool internal;

  /// Monotonic per-thread ordering. Order by this, NOT created_at (#309):
  /// created_at is clock-dependent and two messages can share a timestamp.
  final int seq;

  final DateTime createdAt;
  final DateTime? deletedAt;
  final String? senderUserId;

  /// Retraction deletes the attachment ROWS, so a retracted message always
  /// arrives with this empty regardless of what it once carried.
  final List<SupportAttachment> attachments;

  const SupportMessage({
    required this.id,
    required this.ticketId,
    required this.sender,
    required this.body,
    required this.internal,
    required this.seq,
    required this.createdAt,
    this.deletedAt,
    this.senderUserId,
    this.attachments = const [],
  });

  bool get isRetracted => deletedAt != null;
  bool get isFromAgent => sender == 'agent';
  bool get isSystem => sender == 'system';

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: j['id'].toString(),
        ticketId: j['ticket_id'].toString(),
        sender: (j['sender'] ?? 'requester').toString(),
        body: (j['body'] ?? '').toString(),
        internal: j['internal'] == true,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        deletedAt: j['deleted_at'] == null
            ? null
            : DateTime.tryParse(j['deleted_at'].toString())?.toLocal(),
        senderUserId: j['sender_user_id']?.toString(),
        attachments: ((j['support_attachments'] as List?) ?? const [])
            .map((a) => SupportAttachment.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
      );
}

/// A file on a support message.
///
/// Lives in the PRIVATE `support-attachments` bucket, so it is never reachable
/// by URL — every render needs a freshly signed URL. Web chose private over
/// public deliberately (#308): these are screenshots of payment failures, bank
/// details and IDs, and a public bucket URL is permanent and unauthenticated.
class SupportAttachment {
  final String id;
  final String messageId;

  /// Always `<ticket_id>/<file>`: the storage RLS policy matches the FIRST path
  /// segment against the ticket, so a path shaped any other way is rejected.
  final String storagePath;

  final String fileName;
  final String mimeType;
  final int sizeBytes;

  const SupportAttachment({
    required this.id,
    required this.messageId,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  bool get isImage => mimeType.startsWith('image/');

  factory SupportAttachment.fromJson(Map<String, dynamic> j) =>
      SupportAttachment(
        id: j['id'].toString(),
        messageId: j['message_id']?.toString() ?? '',
        storagePath: (j['storage_path'] ?? '').toString(),
        fileName: (j['file_name'] ?? 'Attachment').toString(),
        mimeType: (j['mime_type'] ?? '').toString(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      );
}

/// A support thread's header row.
class SupportTicket {
  final String id;

  /// Human-facing id an agent and a user can both say out loud ("HH-1042").
  final String? reference;

  final String subject;

  /// 'open' | 'pending' | 'resolved' | 'closed'.
  final String status;

  /// 'payouts' | 'events' | 'tickets' | 'account' | 'technical' | 'other'.
  final String category;

  final DateTime? lastMessageAt;
  final DateTime createdAt;

  const SupportTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.status,
    required this.category,
    required this.lastMessageAt,
    required this.createdAt,
  });

  /// Closed is FINAL (#316): replying is refused by RLS with a bare, reasonless
  /// error, so the composer must be swapped for a "start a new ticket"
  /// affordance BEFORE the user types — never by letting the insert fail.
  /// Resolved still accepts a reply, and replying reopens the thread.
  bool get isClosed => status == 'closed';
  bool get isResolved => status == 'resolved';

  /// Finished from the USER's point of view: resolved OR closed (Rich's call,
  /// 2026-09-15). Web's model lets a reply reopen a resolved thread; the app
  /// deliberately does not offer that — once support says it is done, the
  /// chat ends and the next contact is a fresh ticket. Only `isClosed` is the
  /// RLS-final state; this is the UI-final one.
  bool get isFinished => isResolved || isClosed;
  bool get isActive => !isFinished;

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: j['id'].toString(),
        reference: j['reference']?.toString(),
        subject: (j['subject'] ?? 'Support').toString(),
        status: (j['status'] ?? 'open').toString(),
        category: (j['category'] ?? 'other').toString(),
        lastMessageAt: DateTime.tryParse(
          j['last_message_at']?.toString() ?? '',
        )?.toLocal(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

/// The categories the requester may pick. Mirrors the CHECK on
/// `support_tickets.category`, minus 'payouts', which is an organizer concern
/// and would route an app user into the wrong queue.
enum SupportCategory {
  tickets('tickets', 'Tickets & orders'),
  events('events', 'Events'),
  account('account', 'My account'),
  technical('technical', 'Something is broken'),
  other('other', 'Something else');

  const SupportCategory(this.value, this.label);
  final String value;
  final String label;
}
