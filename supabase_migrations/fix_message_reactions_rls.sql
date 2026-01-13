-- Fix RLS policies for message_reactions table

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can view reactions" ON public.message_reactions;
DROP POLICY IF EXISTS "Users can add reactions" ON public.message_reactions;
DROP POLICY IF EXISTS "Users can remove their own reactions" ON public.message_reactions;

-- Enable RLS
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view reactions
CREATE POLICY "Users can view reactions" ON public.message_reactions
  FOR SELECT USING (true);

-- Policy: Authenticated users can add reactions
CREATE POLICY "Users can add reactions" ON public.message_reactions
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
  );

-- Policy: Users can delete their own reactions
CREATE POLICY "Users can remove their own reactions" ON public.message_reactions
  FOR DELETE USING (
    auth.uid() = user_id
  );

-- Grant permissions
GRANT SELECT, INSERT, DELETE ON public.message_reactions TO authenticated;
GRANT SELECT ON public.message_reactions TO anon;
