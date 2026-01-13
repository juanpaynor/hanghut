-- Add missing columns to messages table for GIF support and message types

-- Add gif_url column
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS gif_url TEXT;

-- Add message_type/content_type column (for text, gif, image, etc.)
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS content_type TEXT DEFAULT 'text';

-- Add reply_to_id for threaded conversations
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL;

-- Add sender_name for faster queries (denormalized)
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS sender_name TEXT;

-- Create index for reply threads
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON public.messages(reply_to_id);

-- Update RLS policies to allow GIF messages (if needed)
-- The existing policies should already cover this, but let's ensure they exist

DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
CREATE POLICY "Participants can view messages" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.table_participants tp
      WHERE tp.table_id = messages.table_id
      AND tp.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.tables t
      WHERE t.id = messages.table_id
      AND t.host_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Participants can send messages" ON public.messages;
CREATE POLICY "Participants can send messages" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND (
      EXISTS (
        SELECT 1 FROM public.table_participants tp
        WHERE tp.table_id = messages.table_id
        AND tp.user_id = auth.uid()
      )
      OR
      EXISTS (
        SELECT 1 FROM public.tables t
        WHERE t.id = messages.table_id
        AND t.host_id = auth.uid()
      )
    )
  );
