-- Add notification_preferences column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS notification_preferences JSONB 
DEFAULT jsonb_build_object(
  'event_joins', true,
  'chat_messages', true,
  'post_likes', true,
  'post_comments', true,
  'event_updates', true
);

-- Allow users to update their own notification preferences
DROP POLICY IF EXISTS "Users can update their own notification_preferences" ON users;
CREATE POLICY "Users can update their own notification_preferences" 
ON users FOR UPDATE 
USING (auth.uid() = id) 
WITH CHECK (auth.uid() = id);
