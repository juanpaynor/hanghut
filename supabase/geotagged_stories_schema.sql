-- ==========================================
-- PHASE 8: Geotagged Visual Stories Schema
-- ==========================================

-- 1. Add new columns to the existing public.posts table
ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS table_id uuid REFERENCES public.tables(id),
ADD COLUMN IF NOT EXISTS is_story boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS vibe_tag text,
ADD COLUMN IF NOT EXISTS external_place_id text,
ADD COLUMN IF NOT EXISTS external_place_name text;
-- Note: The 'visibility' column already exists in your schema with the exact 
-- constraints we need (public, followers, private). No need to add it!

-- 2. Create index on event_id and table_id to make clustering queries fast
CREATE INDEX IF NOT EXISTS idx_posts_event_id ON public.posts(event_id);
CREATE INDEX IF NOT EXISTS idx_posts_table_id ON public.posts(table_id);
CREATE INDEX IF NOT EXISTS idx_posts_external_place_id ON public.posts(external_place_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at);

-- 3. Update RLS (Row Level Security) for posts
-- First, drop the old select policy if it exists (assuming it was called 'view_posts_policy')
-- Note: Replace 'view_posts_policy' with the actual name of your current SELECT policy on posts if it's different.
-- DROP POLICY IF EXISTS "view_posts_policy" ON public.posts;

CREATE POLICY "geotagged_stories_view_policy" ON public.posts FOR SELECT USING (
  -- 1. Everyone can see 'public' posts
  visibility = 'public'
  OR 
  -- 2. You can see your own posts
  user_id = auth.uid()
  OR 
  -- 3. You can see 'followers' posts IF you follow the author
  (
    visibility = 'followers' 
    AND 
    EXISTS (SELECT 1 FROM public.follows WHERE follower_id = auth.uid() AND following_id = posts.user_id)
  )
);

-- 4. Create the 'map_live_stories_view' 
-- This view automatically filters to only show stories from the last 24 hours.
-- It groups the posts by location so the map can efficiently fetch markers.
CREATE OR REPLACE VIEW public.map_live_stories_view AS
SELECT 
    p.event_id,
    p.table_id,
    p.external_place_id,
    p.external_place_name,
    p.latitude,
    p.longitude,
    count(p.id) as story_count,
    max(p.created_at) as latest_story_time
FROM 
    public.posts p
WHERE 
    p.is_story = true 
    AND p.created_at > (NOW() - INTERVAL '24 hours')
    -- We assume RLS automatically filters the underlying 'posts' table based on the user querying the view.
GROUP BY 
    p.event_id, p.table_id, p.external_place_id, p.external_place_name, p.latitude, p.longitude;
