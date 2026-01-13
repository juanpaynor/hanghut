-- Fix reply_to_id foreign key constraint to allow replies to local-only messages

-- Drop the existing foreign key constraint
ALTER TABLE public.messages 
DROP CONSTRAINT IF EXISTS messages_reply_to_id_fkey;

-- Add it back as a nullable constraint (ON DELETE SET NULL)
-- This allows replies even if the original message doesn't exist in Supabase yet
ALTER TABLE public.messages 
ADD CONSTRAINT messages_reply_to_id_fkey 
FOREIGN KEY (reply_to_id) 
REFERENCES public.messages(id) 
ON DELETE SET NULL;

-- Note: This allows replies to work in Telegram mode where messages
-- are stored locally first and synced later
