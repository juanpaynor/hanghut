# Complete Schema Fix Guide

## Required Supabase Migrations (Run in order):

1. `add_messages_gif_support.sql` - Adds gif_url, content_type, reply_to_id columns
2. `fix_message_reactions_rls.sql` - Fixes RLS policies for reactions
3. `fix_reply_foreign_key.sql` - Makes reply_to_id nullable
4. `fix_reactions_foreign_key.sql` - Makes message_id deferrable
5. `fix_map_view_show_recent.sql` - Shows last 24 hours of tables
6. `fix_feed_show_all_posts.sql` - Shows global posts

## Code Fixes Applied:
- Reaction handler checks if message exists in Supabase first
- Reply sync skips reply_to_id if original message not synced
- Message sync uses upsert to avoid duplicates
- Instagram-style floating emoji picker
- Double-tap to react with heart
