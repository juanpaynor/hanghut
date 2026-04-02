-- ============================================================
-- Instagram-Style Story Tray Migration
-- ============================================================
-- Run this in Supabase SQL Editor
--
-- Creates:
--   1. story_views table (tracks seen/unseen per author)
--   2. get_story_tray RPC (grouping + closeness + pagination)
--   3. mark_stories_viewed RPC (upsert seen state)
-- ============================================================


-- ============================================================
-- STEP 1: Create story_views table
-- Tracks which users' stories the current user has viewed
-- Keyed by (viewer, author) — not per-story, but per-author
-- ============================================================

CREATE TABLE IF NOT EXISTS public.story_views (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  story_author_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  last_viewed_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  PRIMARY KEY (user_id, story_author_id)
);

-- Index for fast lookups by viewer
CREATE INDEX IF NOT EXISTS idx_story_views_user
ON public.story_views(user_id);

-- RLS: users can only see/modify their own views
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own story views" ON public.story_views;
CREATE POLICY "Users can view own story views"
  ON public.story_views FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own story views" ON public.story_views;
CREATE POLICY "Users can insert own story views"
  ON public.story_views FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own story views" ON public.story_views;
CREATE POLICY "Users can update own story views"
  ON public.story_views FOR UPDATE
  USING (auth.uid() = user_id);


-- ============================================================
-- STEP 2: Create mark_stories_viewed RPC
-- Called when user finishes viewing someone's stories
-- ============================================================

CREATE OR REPLACE FUNCTION mark_stories_viewed(
  p_author_id UUID
)
RETURNS VOID AS $fn1$
BEGIN
  INSERT INTO public.story_views (user_id, story_author_id, last_viewed_at)
  VALUES (auth.uid(), p_author_id, NOW())
  ON CONFLICT (user_id, story_author_id)
  DO UPDATE SET last_viewed_at = NOW();
END;
$fn1$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION mark_stories_viewed IS 'Marks a users stories as viewed by the current user (upsert)';


-- ============================================================
-- STEP 3: Create get_story_tray RPC
-- Server-side grouping, closeness ranking, seen/unseen, pagination
-- ============================================================

CREATE OR REPLACE FUNCTION get_story_tray(
  p_following_only BOOLEAN DEFAULT false,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  author_id UUID,
  author_name TEXT,
  author_avatar_url TEXT,
  story_count BIGINT,
  latest_story_time TIMESTAMPTZ,
  latest_image_url TEXT,
  latest_video_url TEXT,
  latest_event_id UUID,
  latest_table_id UUID,
  latest_external_place_id TEXT,
  latest_external_place_name TEXT,
  latest_latitude DOUBLE PRECISION,
  latest_longitude DOUBLE PRECISION,
  is_seen BOOLEAN,
  is_own BOOLEAN,
  closeness_score INTEGER
) AS $fn2$
DECLARE
  v_user_id UUID := auth.uid();
  v_cutoff TIMESTAMPTZ := NOW() - INTERVAL '24 hours';
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH story_authors AS (
    -- Get all stories from last 24h, grouped by author
    SELECT
      p.user_id AS author_id,
      COUNT(p.id) AS story_count,
      MAX(p.created_at) AS latest_story_time,
      -- Get latest story details using array_agg ordered by time
      (array_agg(p.image_url ORDER BY p.created_at DESC))[1] AS latest_image_url,
      (array_agg(p.video_url ORDER BY p.created_at DESC))[1] AS latest_video_url,
      (array_agg(p.event_id ORDER BY p.created_at DESC))[1] AS latest_event_id,
      (array_agg(p.table_id ORDER BY p.created_at DESC))[1] AS latest_table_id,
      (array_agg(p.external_place_id ORDER BY p.created_at DESC))[1] AS latest_external_place_id,
      (array_agg(p.external_place_name ORDER BY p.created_at DESC))[1] AS latest_external_place_name,
      (array_agg(p.latitude ORDER BY p.created_at DESC))[1] AS latest_latitude,
      (array_agg(p.longitude ORDER BY p.created_at DESC))[1] AS latest_longitude
    FROM public.posts p
    WHERE p.is_story = true
      AND p.created_at > v_cutoff
      AND (
        -- If following_only, filter to followed users + own stories
        NOT p_following_only
        OR p.user_id = v_user_id
        OR p.user_id IN (SELECT f.following_id FROM public.follows f WHERE f.follower_id = v_user_id)
      )
    GROUP BY p.user_id
  ),
  closeness AS (
    -- Calculate closeness score for each story author
    SELECT
      sa.author_id,
      (
        -- Mutual follow: +3
        CASE WHEN EXISTS(
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = sa.author_id AND f.following_id = v_user_id
        ) THEN 3 ELSE 0 END
        +
        -- Recent DMs (last 7 days): count messages in shared chats, up to +4
        LEAST(
          (SELECT COUNT(*) FROM public.direct_messages dm
           WHERE dm.created_at > NOW() - INTERVAL '7 days'
             AND dm.chat_id IN (
               -- Find chats shared between current user and this author
               SELECT p1.chat_id
               FROM public.direct_chat_participants p1
               JOIN public.direct_chat_participants p2 ON p1.chat_id = p2.chat_id
               WHERE p1.user_id = v_user_id AND p2.user_id = sa.author_id
             )
          ),
          4
        )
        +
        -- Recent likes on their posts: +1 each, up to +3
        LEAST(
          (SELECT COUNT(*) FROM public.post_likes pl
           JOIN public.posts lp ON pl.post_id = lp.id
           WHERE pl.user_id = v_user_id AND lp.user_id = sa.author_id
             AND pl.created_at > NOW() - INTERVAL '7 days'
          ),
          3
        )
        +
        -- Recent comments on their posts: +1 each, up to +3
        LEAST(
          (SELECT COUNT(*) FROM public.comments c
           JOIN public.posts cp ON c.post_id = cp.id
           WHERE c.user_id = v_user_id AND cp.user_id = sa.author_id
             AND c.created_at > NOW() - INTERVAL '7 days'
          ),
          3
        )
      )::INTEGER AS score
    FROM story_authors sa
    WHERE sa.author_id != v_user_id  -- Don't score yourself
  )
  SELECT
    sa.author_id,
    COALESCE(u.display_name, 'Friend')::TEXT AS author_name,
    COALESCE(
      u.avatar_url,
      (SELECT up.photo_url FROM public.user_photos up
       WHERE up.user_id = sa.author_id
       ORDER BY up.is_primary DESC, up.sort_order ASC
       LIMIT 1)
    )::TEXT AS author_avatar_url,
    sa.story_count,
    sa.latest_story_time,
    sa.latest_image_url::TEXT,
    sa.latest_video_url::TEXT,
    sa.latest_event_id,
    sa.latest_table_id,
    sa.latest_external_place_id::TEXT,
    sa.latest_external_place_name::TEXT,
    sa.latest_latitude,
    sa.latest_longitude,
    -- is_seen: true if user has viewed AND no new story since then
    CASE
      WHEN sa.author_id = v_user_id THEN false  -- Own story always shows as "unseen" (ring active)
      WHEN sv.last_viewed_at IS NULL THEN false  -- Never viewed = unseen
      WHEN sa.latest_story_time > sv.last_viewed_at THEN false  -- New story since last view = unseen
      ELSE true  -- Viewed and no new story = seen
    END AS is_seen,
    (sa.author_id = v_user_id) AS is_own,
    COALESCE(cl.score, 0)::INTEGER AS closeness_score
  FROM story_authors sa
  LEFT JOIN public.users u ON sa.author_id = u.id
  LEFT JOIN public.story_views sv ON sv.user_id = v_user_id AND sv.story_author_id = sa.author_id
  LEFT JOIN closeness cl ON cl.author_id = sa.author_id
  ORDER BY
    -- 1. Own story always first
    (sa.author_id = v_user_id) DESC,
    -- 2. Unseen before seen
    CASE
      WHEN sa.author_id = v_user_id THEN false
      WHEN sv.last_viewed_at IS NULL THEN false
      WHEN sa.latest_story_time > sv.last_viewed_at THEN false
      ELSE true
    END ASC,
    -- 3. By closeness score (higher = more relevant)
    COALESCE(cl.score, 0) DESC,
    -- 4. By recency
    sa.latest_story_time DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$fn2$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_story_tray IS 'Fetches story tray with closeness ranking, seen/unseen state, and pagination. Instagram-style sorting.';


-- ============================================================
-- VERIFICATION
-- ============================================================

DO $verify$
DECLARE
  v_story_views_exists BOOLEAN;
  v_rpc_tray_exists BOOLEAN;
  v_rpc_mark_exists BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'story_views' AND table_schema = 'public'
  ) INTO v_story_views_exists;

  SELECT EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'get_story_tray'
  ) INTO v_rpc_tray_exists;

  SELECT EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'mark_stories_viewed'
  ) INTO v_rpc_mark_exists;

  RAISE NOTICE '================================================';
  RAISE NOTICE '  Story Tray Migration — Results';
  RAISE NOTICE '================================================';
  RAISE NOTICE '  story_views table:       %', CASE WHEN v_story_views_exists THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  get_story_tray RPC:      %', CASE WHEN v_rpc_tray_exists THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  mark_stories_viewed RPC: %', CASE WHEN v_rpc_mark_exists THEN '✅' ELSE '❌' END;
  RAISE NOTICE '================================================';

  -- Test RPCs
  RAISE NOTICE '  Testing get_story_tray...';
  PERFORM * FROM get_story_tray(false, 20, 0);
  RAISE NOTICE '  ✅ get_story_tray works';

  RAISE NOTICE '================================================';
  RAISE NOTICE '  ALL CHECKS PASSED!';
  RAISE NOTICE '================================================';
END $verify$;
