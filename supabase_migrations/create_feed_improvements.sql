-- ============================================================
-- Feed Improvements Migration
-- Adds: post_bookmarks table, calculate_distance function,
--        get_following_feed RPC, updated get_philippines_feed RPC
-- ============================================================

-- 1. Bookmarks Table
CREATE TABLE IF NOT EXISTS public.post_bookmarks (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (user_id, post_id)
);

-- RLS for Bookmarks
ALTER TABLE public.post_bookmarks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own bookmarks" ON public.post_bookmarks;
CREATE POLICY "Users can view their own bookmarks" 
    ON public.post_bookmarks FOR SELECT 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can add bookmarks" ON public.post_bookmarks;
CREATE POLICY "Users can add bookmarks" 
    ON public.post_bookmarks FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can remove bookmarks" ON public.post_bookmarks;
CREATE POLICY "Users can remove bookmarks" 
    ON public.post_bookmarks FOR DELETE 
    USING (auth.uid() = user_id);

-- 2. Calculate Distance Function (Haversine formula, returns meters)
CREATE OR REPLACE FUNCTION public.calculate_distance(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  R CONSTANT integer := 6371000; -- Earth radius in meters
  dLat double precision;
  dLon double precision;
  a double precision;
  c double precision;
BEGIN
  dLat := radians(lat2 - lat1);
  dLon := radians(lon2 - lon1);
  a := sin(dLat/2)^2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dLon/2)^2;
  c := 2 * asin(sqrt(a));
  RETURN R * c;
END;
$$;

-- 3. Following Feed RPC
-- Drop ALL old overloads to prevent ambiguity
DROP FUNCTION IF EXISTS public.get_following_feed(INT, TIMESTAMP WITHOUT TIME ZONE, UUID, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_following_feed(INT, TIMESTAMP WITH TIME ZONE, UUID, DOUBLE PRECISION, DOUBLE PRECISION);

-- Returns posts from people the current user follows + own posts
CREATE OR REPLACE FUNCTION public.get_following_feed(
  p_limit INT,
  p_cursor TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_user_lat DOUBLE PRECISION DEFAULT NULL,
  p_user_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id UUID;
  v_posts JSONB;
BEGIN
  v_user_id := auth.uid();

  SELECT jsonb_agg(row_data)
  INTO v_posts
  FROM (
    SELECT jsonb_build_object(
      'id', p.id,
      'user_id', p.user_id,
      'content', p.content,
      'image_url', p.image_url,
      'image_urls', p.image_urls,
      'gif_url', p.gif_url,
      'video_url', p.video_url,
      'event_id', p.event_id,
      'post_type', p.post_type,
      'metadata', p.metadata,
      'created_at', p.created_at,
      'user_data', (
        SELECT jsonb_build_object(
          'id', u.id,
          'display_name', u.display_name,
          'avatar_url', COALESCE(
            u.avatar_url,
            (SELECT photo_url FROM public.user_photos up WHERE up.user_id = u.id AND up.is_primary = true LIMIT 1),
            (SELECT photo_url FROM public.user_photos up WHERE up.user_id = u.id ORDER BY up.uploaded_at DESC LIMIT 1)
          )
        )
        FROM public.users u
        WHERE u.id = p.user_id
      ),
      'likes_count', (SELECT COUNT(*) FROM public.post_likes pl WHERE pl.post_id = p.id),
      'comment_count', (SELECT COUNT(*) FROM public.comments c WHERE c.post_id = p.id),
      'user_has_liked', (
        CASE WHEN v_user_id IS NOT NULL THEN
          EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = v_user_id)
        ELSE false END
      ),
      'user_has_bookmarked', (
        CASE WHEN v_user_id IS NOT NULL THEN
          EXISTS(SELECT 1 FROM public.post_bookmarks pb WHERE pb.post_id = p.id AND pb.user_id = v_user_id)
        ELSE false END
      ),
      'distance_meters', (
        CASE 
          WHEN p.latitude IS NOT NULL AND p.longitude IS NOT NULL AND p_user_lat IS NOT NULL AND p_user_lng IS NOT NULL THEN
            public.calculate_distance(p.latitude, p.longitude, p_user_lat, p_user_lng)
          ELSE NULL 
        END
      )
    ) AS row_data
    FROM public.posts p
    WHERE 
      (
        p.user_id IN (SELECT following_id FROM public.follows WHERE follower_id = v_user_id) 
        OR 
        p.user_id = v_user_id
      )
      AND
      (p_cursor IS NULL OR (p.created_at < p_cursor OR (p.created_at = p_cursor AND p.id < p_cursor_id)))
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT p_limit
  ) sub;

  RETURN COALESCE(v_posts, '[]'::jsonb);
END;
$$;

-- 4. Philippines-wide Feed RPC (all posts, no follow filter)
-- Drop ALL old overloads to prevent ambiguity
DROP FUNCTION IF EXISTS public.get_philippines_feed(INT, TIMESTAMP WITHOUT TIME ZONE, UUID, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_philippines_feed(INT, TIMESTAMP WITH TIME ZONE, UUID, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.get_philippines_feed(
  p_limit INT,
  p_cursor TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_user_lat DOUBLE PRECISION DEFAULT NULL,
  p_user_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id UUID;
  v_posts JSONB;
BEGIN
  v_user_id := auth.uid();

  SELECT jsonb_agg(row_data)
  INTO v_posts
  FROM (
    SELECT jsonb_build_object(
      'id', p.id,
      'user_id', p.user_id,
      'content', p.content,
      'image_url', p.image_url,
      'image_urls', p.image_urls,
      'gif_url', p.gif_url,
      'video_url', p.video_url,
      'event_id', p.event_id,
      'post_type', p.post_type,
      'metadata', p.metadata,
      'created_at', p.created_at,
      'user_data', (
        SELECT jsonb_build_object(
          'id', u.id,
          'display_name', u.display_name,
          'avatar_url', COALESCE(
            u.avatar_url,
            (SELECT photo_url FROM public.user_photos up WHERE up.user_id = u.id AND up.is_primary = true LIMIT 1),
            (SELECT photo_url FROM public.user_photos up WHERE up.user_id = u.id ORDER BY up.uploaded_at DESC LIMIT 1)
          )
        )
        FROM public.users u
        WHERE u.id = p.user_id
      ),
      'likes_count', (SELECT COUNT(*) FROM public.post_likes pl WHERE pl.post_id = p.id),
      'comment_count', (SELECT COUNT(*) FROM public.comments c WHERE c.post_id = p.id),
      'user_has_liked', (
        CASE WHEN v_user_id IS NOT NULL THEN
          EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id = p.id AND pl.user_id = v_user_id)
        ELSE false END
      ),
      'user_has_bookmarked', (
        CASE WHEN v_user_id IS NOT NULL THEN
          EXISTS(SELECT 1 FROM public.post_bookmarks pb WHERE pb.post_id = p.id AND pb.user_id = v_user_id)
        ELSE false END
      ),
      'distance_meters', (
        CASE 
          WHEN p.latitude IS NOT NULL AND p.longitude IS NOT NULL AND p_user_lat IS NOT NULL AND p_user_lng IS NOT NULL THEN
            public.calculate_distance(p.latitude, p.longitude, p_user_lat, p_user_lng)
          ELSE NULL 
        END
      )
    ) AS row_data
    FROM public.posts p
    WHERE 
      (p_cursor IS NULL OR (p.created_at < p_cursor OR (p.created_at = p_cursor AND p.id < p_cursor_id)))
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT p_limit
  ) sub;

  RETURN COALESCE(v_posts, '[]'::jsonb);
END;
$$;
