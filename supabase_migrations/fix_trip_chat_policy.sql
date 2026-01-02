-- Enable RLS
ALTER TABLE public.trip_chat_participants ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can join trip chats" ON public.trip_chat_participants;
DROP POLICY IF EXISTS "Users can update their own trip chat participation" ON public.trip_chat_participants;
DROP POLICY IF EXISTS "Authenticated users can view trip chat participants" ON public.trip_chat_participants;

-- Allow users to insert THEMSELVES into the participants table
CREATE POLICY "Users can join trip chats"
    ON public.trip_chat_participants
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Allow users to update THEIR OWN record (e.g. last_read_at)
CREATE POLICY "Users can update their own trip chat participation"
    ON public.trip_chat_participants
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Allow users to view participants of chats they are in or if the chat is public (depending on requirements)
-- For now, let's allow viewing if they are authenticated, as discovering who is in a chat might be needed before joining
CREATE POLICY "Authenticated users can view trip chat participants"
    ON public.trip_chat_participants
    FOR SELECT
    TO authenticated
    USING (true);
