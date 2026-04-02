-- ==========================================
-- Story Views Table
-- Tracks which users have viewed each story
-- ==========================================

-- 1. Drop any previous version
DROP TABLE IF EXISTS public.story_views CASCADE;

-- 2. Create table (no FK constraints to avoid schema issues)
CREATE TABLE public.story_views (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id uuid NOT NULL,
  viewer_id uuid NOT NULL,
  viewed_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE(post_id, viewer_id)
);

-- 3. Indexes for fast lookups
CREATE INDEX idx_story_views_post_id ON public.story_views(post_id);
CREATE INDEX idx_story_views_viewer_id ON public.story_views(viewer_id);

-- 4. RLS
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own views"
  ON public.story_views FOR INSERT
  WITH CHECK (auth.uid() = viewer_id);

CREATE POLICY "Authors and viewers can read views"
  ON public.story_views FOR SELECT
  USING (
    auth.uid() = viewer_id
    OR EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = story_views.post_id
      AND p.user_id = auth.uid()
    )
  );

-- 5. Cleanup function for expired stories
CREATE OR REPLACE FUNCTION public.cleanup_expired_story_views()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM public.story_views sv
  WHERE sv.post_id IN (
    SELECT p.id FROM public.posts p
    WHERE p.is_story = true
    AND p.created_at < (NOW() - INTERVAL '24 hours')
  );
$$;
