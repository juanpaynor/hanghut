-- Add reply and reaction support to messages table
ALTER TABLE public.messages
ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS deleted_for_everyone BOOLEAN DEFAULT FALSE;

-- Create message reactions table
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON public.message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id ON public.message_reactions(user_id);

-- Enable RLS on message_reactions
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read reactions from tables they're a member of
CREATE POLICY "Users can read reactions from their tables"
ON public.message_reactions
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.messages m
    INNER JOIN public.table_members tm ON tm.table_id = m.table_id
    WHERE m.id = message_reactions.message_id
    AND tm.user_id = auth.uid()
    AND tm.status IN ('approved', 'joined', 'attended')
  )
  OR
  EXISTS (
    SELECT 1 FROM public.messages m
    INNER JOIN public.tables t ON t.id = m.table_id
    WHERE m.id = message_reactions.message_id
    AND t.host_id = auth.uid()
  )
);

-- Policy: Users can add reactions to messages in their tables
CREATE POLICY "Users can add reactions to their table messages"
ON public.message_reactions
FOR INSERT
WITH CHECK (
  user_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.messages m
    INNER JOIN public.table_members tm ON tm.table_id = m.table_id
    WHERE m.id = message_reactions.message_id
    AND tm.user_id = auth.uid()
    AND tm.status IN ('approved', 'joined', 'attended')
  )
  OR
  EXISTS (
    SELECT 1 FROM public.messages m
    INNER JOIN public.tables t ON t.id = m.table_id
    WHERE m.id = message_reactions.message_id
    AND t.host_id = auth.uid()
  )
);

-- Policy: Users can delete their own reactions
CREATE POLICY "Users can delete their own reactions"
ON public.message_reactions
FOR DELETE
USING (user_id = auth.uid());
