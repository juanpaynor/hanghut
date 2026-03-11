-- Fix for Emojis in Comments and Chat

-- 1. Create missing comment_reactions table
CREATE TABLE IF NOT EXISTS public.comment_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(comment_id, user_id, emoji)
);
CREATE INDEX IF NOT EXISTS idx_comment_reactions_comment_id ON public.comment_reactions(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_reactions_user_id ON public.comment_reactions(user_id);

-- Enable RLS for comment_reactions
ALTER TABLE public.comment_reactions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can read comment reactions
CREATE POLICY "Public can read comment reactions" 
ON public.comment_reactions FOR SELECT 
USING (true);

-- Policy: Users can add their own reactions
CREATE POLICY "Users can insert their own comment reactions" 
ON public.comment_reactions FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can delete their own reactions
CREATE POLICY "Users can delete their own comment reactions" 
ON public.comment_reactions FOR DELETE 
USING (auth.uid() = user_id);

-- 2. Fix message_reactions to support trip_messages and direct_messages
-- Currently, message_reactions ONLY references public.messages (which is for table chats).
-- For Trips and DMs, we either need a unified messages table, OR we remove the strict foreign key
-- and validate via RLS, or we add trip_message_reactions and direct_message_reactions.
-- Given the Flutter code uses `message_reactions` universally in _syncReactionToBackend:

-- First, let's allow message_reactions to point to ANY message by dropping the strict FK.
-- But wait, taking a closer look at ChatScreen, in `_syncReactionToBackend`, it writes to `message_reactions`.
-- If the ID belongs to `trip_messages` or `direct_messages`, the `messages` FK will fail!

ALTER TABLE public.message_reactions DROP CONSTRAINT IF EXISTS message_reactions_message_id_fkey;

-- We still want policies on message_reactions. 
-- For simplicity without complex joins that check all 3 tables:

DROP POLICY IF EXISTS "Public can read message reactions" ON public.message_reactions;
CREATE POLICY "Public can read message reactions" 
ON public.message_reactions FOR SELECT 
USING (true);

DROP POLICY IF EXISTS "Users can insert their own message reactions" ON public.message_reactions;
CREATE POLICY "Users can insert their own message reactions" 
ON public.message_reactions FOR INSERT 
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own message reactions" ON public.message_reactions;
CREATE POLICY "Users can delete their own message reactions" 
ON public.message_reactions FOR DELETE 
USING (auth.uid() = user_id);
