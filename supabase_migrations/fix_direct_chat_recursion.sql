-- Fix infinite recursion in direct_chat_participants policy
-- The original policy queried itself unconditionally, leading to a loop.
-- We fix this by adding specialized logic: always allow users to see their own rows (base case).

DROP POLICY IF EXISTS "View chat participants" ON public.direct_chat_participants;

CREATE POLICY "View chat participants" ON public.direct_chat_participants
    FOR SELECT USING (
        -- Base case: Prevent recursion by allowing access to own row immediately
        user_id = auth.uid()
        OR 
        -- Recursive case: Allow access to other rows if we share a chat
        -- This subquery resolves safely because viewing *my* row hits the base case above.
        EXISTS (
            SELECT 1 FROM direct_chat_participants p
            WHERE p.chat_id = direct_chat_participants.chat_id 
            AND p.user_id = auth.uid()
        )
    );
