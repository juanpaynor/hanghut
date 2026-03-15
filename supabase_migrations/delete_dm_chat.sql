-- Delete DM Chat for the calling user
-- Removes the user's participant row so the chat disappears from their inbox.
-- If both participants have left, the direct_chat row is deleted entirely
-- (CASCADE will clean up direct_messages automatically).

CREATE OR REPLACE FUNCTION public.delete_dm_chat(p_chat_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  remaining_count INT;
BEGIN
  -- 1. Remove the calling user from the chat
  DELETE FROM direct_chat_participants
  WHERE chat_id = p_chat_id
    AND user_id = auth.uid();

  -- 2. Check if anyone else is still in this chat
  SELECT COUNT(*) INTO remaining_count
  FROM direct_chat_participants
  WHERE chat_id = p_chat_id;

  -- 3. If no participants remain, nuke the whole chat + messages
  IF remaining_count = 0 THEN
    DELETE FROM direct_chats WHERE id = p_chat_id;
  END IF;
END;
$$;
