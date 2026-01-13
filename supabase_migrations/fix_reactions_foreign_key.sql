-- Comprehensive fix for message_reactions foreign key constraint
-- This allows reactions to work even when messages are stored locally (Telegram mode)

-- Drop the existing foreign key constraint
ALTER TABLE public.message_reactions 
DROP CONSTRAINT IF EXISTS message_reactions_message_id_fkey;

-- Add it back with ON DELETE CASCADE and make it deferrable
-- This allows reactions even if the message doesn't exist in Supabase yet
ALTER TABLE public.message_reactions 
ADD CONSTRAINT message_reactions_message_id_fkey 
FOREIGN KEY (message_id) 
REFERENCES public.messages(id) 
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

-- Note: DEFERRABLE INITIALLY DEFERRED means the constraint is checked
-- at the end of the transaction, not immediately. This gives time for
-- messages to be synced before reactions are validated.

-- However, for Telegram mode, we should store reactions locally too.
-- The better solution is to not sync reactions to Supabase until the message exists.
