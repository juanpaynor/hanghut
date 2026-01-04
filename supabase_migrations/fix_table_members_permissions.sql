-- Fix missing RLS policies for table_members
-- The code uses 'table_members' but previous migrations only added SELECT policies.
-- This prevented users from Joining (INSERT) or Leaving (UPDATE) tables.

ALTER TABLE public.table_members ENABLE ROW LEVEL SECURITY;

-- 1. Allow users to JOIN tables (Insert their own record)
DROP POLICY IF EXISTS "Users can join tables" ON public.table_members;
CREATE POLICY "Users can join tables"
    ON public.table_members
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 2. Allow users to LEAVE tables (Update their own status)
DROP POLICY IF EXISTS "Users can update their own membership" ON public.table_members;
CREATE POLICY "Users can update their own membership"
    ON public.table_members
    FOR UPDATE
    USING (auth.uid() = user_id);

-- 3. Allow Hosts to manage members (Update status to approved/declined/left)
-- We need to join with the tables table to check if the user is the host
DROP POLICY IF EXISTS "Hosts can manage members" ON public.table_members;
CREATE POLICY "Hosts can manage members"
    ON public.table_members
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.tables
            WHERE id = table_members.table_id
            AND host_id = auth.uid()
        )
    );

-- 4. Allow Hosts to remove members (Update status or Delete?)
-- Service uses UPDATE status='left', so the above Update policy covers it.
-- But if we ever DELETE, let's add DELETE policy for self and host.

DROP POLICY IF EXISTS "Users can delete their own membership" ON public.table_members;
CREATE POLICY "Users can delete their own membership"
    ON public.table_members
    FOR DELETE
    USING (auth.uid() = user_id);
