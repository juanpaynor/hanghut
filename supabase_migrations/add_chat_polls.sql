-- =========================================================================
-- Chat Polls Feature
-- =========================================================================
-- Creates chat_polls and chat_poll_votes tables for in-chat voting.
-- Polls are linked to a chat (table or trip) and NOT available for DMs.

-- 1. Polls
CREATE TABLE IF NOT EXISTS public.chat_polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id TEXT NOT NULL,         -- table_id or trip chat_id
  chat_type TEXT NOT NULL        -- 'table' or 'trip'
    CHECK (chat_type IN ('table', 'trip')),
  creator_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  options JSONB NOT NULL,        -- [{"id":"a","text":"Yes"}, {"id":"b","text":"No"}]
  is_closed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

-- 2. Votes
CREATE TABLE IF NOT EXISTS public.chat_poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID NOT NULL REFERENCES public.chat_polls(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  option_id TEXT NOT NULL,
  voted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (poll_id, user_id)      -- one vote per user per poll
);

-- 3. Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_chat_polls_chat_id ON public.chat_polls(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_poll_votes_poll_id ON public.chat_poll_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_chat_poll_votes_user_id ON public.chat_poll_votes(user_id);

-- 4. RLS
ALTER TABLE public.chat_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_poll_votes ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all polls (filtered by chat in app)
CREATE POLICY "Authenticated users can read polls"
  ON public.chat_polls FOR SELECT
  TO authenticated USING (true);

-- Only creator can insert
CREATE POLICY "Creator can insert poll"
  ON public.chat_polls FOR INSERT
  TO authenticated WITH CHECK (creator_id = auth.uid());

-- Only creator can close poll
CREATE POLICY "Creator can update poll"
  ON public.chat_polls FOR UPDATE
  TO authenticated USING (creator_id = auth.uid());

-- Users can read all votes
CREATE POLICY "Authenticated users can read votes"
  ON public.chat_poll_votes FOR SELECT
  TO authenticated USING (true);

-- Users can insert their own vote
CREATE POLICY "Users can vote"
  ON public.chat_poll_votes FOR INSERT
  TO authenticated WITH CHECK (user_id = auth.uid());

-- Users can change their own vote
CREATE POLICY "Users can update their vote"
  ON public.chat_poll_votes FOR UPDATE
  TO authenticated USING (user_id = auth.uid());

-- Users can delete (un-vote) their own vote
CREATE POLICY "Users can delete their vote"
  ON public.chat_poll_votes FOR DELETE
  TO authenticated USING (user_id = auth.uid());

-- =========================================================================
-- chat-images Supabase Storage Bucket
-- =========================================================================
-- Run in Supabase Dashboard > Storage > New Bucket:
-- Name: chat-images
-- Public: YES (so image URLs work without signed URLs)
-- File size limit: 5MB (we compress before upload so real uploads ~100-200KB)
-- Then add this RLS policy via SQL:

INSERT: authenticated users can upload
CREATE POLICY "Authenticated users can upload chat images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'chat-images');

SELECT: public read (already enabled by public bucket)
