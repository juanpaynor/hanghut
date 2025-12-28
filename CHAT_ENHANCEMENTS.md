# Chat Enhancement Implementation Plan

## Database Migration
Run: `supabase/migrations/enhance_chat_features.sql`
This adds:
- `reply_to_id` column to messages (for replies)
- `deleted_at` and `deleted_for_everyone` columns (for delete functionality)
- `message_reactions` table (for emoji reactions)
- RLS policies for reactions

## Features to Implement

### 1. Reply to Message
**UI Changes:**
- Long press on message → show context menu with "Reply" option
- Show reply preview above input field when replying
- Display replied-to message in a compact format above the message

**Data Changes:**
- Store `reply_to_id` when sending a message
- Fetch replied-to message data when loading messages
- Show reply thread indicator in message bubble

### 2. Emoji Reactions
**UI Changes:**
- Long press on message → show emoji picker
- Display reactions below message bubble
- Show count for each emoji type
- Clicking reaction adds/removes user's reaction

**Data Changes:**
- Insert into `message_reactions` table
- Subscribe to reactions changes via Supabase realtime
- Group reactions by emoji, show count + user list on tap

### 3. Delete Message
**UI Changes:**
- Long press on own message → show "Delete for me" and "Delete for everyone" options
- Show "[Message deleted]" placeholder for deleted messages
- Host sees additional option to delete any message

**Data Changes:**
- Update `deleted_at` timestamp
- Set `deleted_for_everyone` flag if deleting for all
- Filter out deleted messages (or show placeholder) when loading

### 4. Host Can Kick User
**UI Changes:**
- Long press on message from another user → Host sees "Kick User" option
- Show confirmation dialog
- Remove user from chat and table

**Data Changes:**
- Update table_members status to 'kicked'
- Remove from Ably channel
- Redirect kicked user out of chat

## Implementation Steps

1. **Run migration first**
2. **Add message actions menu** (long press handler)
3. **Implement reply feature** (UI + data)
4. **Add emoji reactions** (picker + display)
5. **Add delete functionality** (soft delete logic)
6. **Add kick functionality** (host-only permission check)

## Code Structure Recommendations

```dart
// Add to ChatScreen state
Map<String, dynamic>? _replyingTo;
bool _isHost = false;

// New widgets to create
Widget _buildMessageActions(message) // Context menu
Widget _buildReplyPreview() // Above input when replying
Widget _buildReactions(message) // Below message bubble
Widget _buildDeletedMessage() // Placeholder for deleted

// New methods
void _handleReply(message)
void _handleReaction(message, emoji)
void _handleDelete(message, deleteForEveryone)
void _handleKick(userId)
```

## Next: Run the migration, then I'll help implement these features one by one.
