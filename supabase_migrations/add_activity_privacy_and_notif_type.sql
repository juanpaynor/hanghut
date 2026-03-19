-- ============================================
-- Friends Going Feature: Privacy + Notification Type
-- ============================================

-- 1. Add privacy toggle to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS
  hide_activity_from_friends BOOLEAN DEFAULT false;

-- 2. Update notifications type constraint to include 'friend_joined'
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'like', 'comment', 'join_request', 'approved',
    'system', 'invite', 'chat', 'friend_joined'
  ]));
