-- Fix infinite recursion by using a SECURITY DEFINER function
-- This bypasses RLS when checking membership, preventing loops.

-- 1. Create Helper Function
CREATE OR REPLACE FUNCTION is_direct_chat_member(target_chat_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM direct_chat_participants
    WHERE chat_id = target_chat_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Update Policies

-- Table: direct_chats
DROP POLICY IF EXISTS "Participants can view chats" ON direct_chats;
CREATE POLICY "Participants can view chats" ON direct_chats
    FOR SELECT USING (is_direct_chat_member(id));

DROP POLICY IF EXISTS "Participants can update chats" ON direct_chats;
CREATE POLICY "Participants can update chats" ON direct_chats
    FOR UPDATE USING (is_direct_chat_member(id));

-- Table: direct_chat_participants
DROP POLICY IF EXISTS "View chat participants" ON direct_chat_participants;
CREATE POLICY "View chat participants" ON direct_chat_participants
    FOR SELECT USING (
        user_id = auth.uid() -- Can always see self
        OR
        is_direct_chat_member(chat_id) -- Can see others in my chats
    );

-- Table: direct_messages
DROP POLICY IF EXISTS "View messages" ON direct_messages;
CREATE POLICY "View messages" ON direct_messages
    FOR SELECT USING (is_direct_chat_member(chat_id));

DROP POLICY IF EXISTS "Send messages" ON direct_messages;
CREATE POLICY "Send messages" ON direct_messages
    FOR INSERT WITH CHECK (
        auth.uid() = sender_id AND
        is_direct_chat_member(chat_id)
    );
