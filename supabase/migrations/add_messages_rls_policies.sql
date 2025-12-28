-- Enable RLS on messages table
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read messages from tables they're a member of
CREATE POLICY "Users can read messages from their tables"
ON public.messages
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.table_members
    WHERE table_members.table_id = messages.table_id
    AND table_members.user_id = auth.uid()
    AND table_members.status IN ('approved', 'joined', 'attended')
  )
  OR
  EXISTS (
    SELECT 1 FROM public.tables
    WHERE tables.id = messages.table_id
    AND tables.host_id = auth.uid()
  )
);

-- Policy: Users can insert messages to tables they're a member of
CREATE POLICY "Users can send messages to their tables"
ON public.messages
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.table_members
    WHERE table_members.table_id = messages.table_id
    AND table_members.user_id = auth.uid()
    AND table_members.status IN ('approved', 'joined', 'attended')
  )
  OR
  EXISTS (
    SELECT 1 FROM public.tables
    WHERE tables.id = messages.table_id
    AND tables.host_id = auth.uid()
  )
);

-- Policy: Users can update their own messages
CREATE POLICY "Users can update their own messages"
ON public.messages
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Policy: Users can delete their own messages
CREATE POLICY "Users can delete their own messages"
ON public.messages
FOR DELETE
USING (user_id = auth.uid());
