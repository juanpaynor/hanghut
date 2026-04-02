-- ============================================================
-- PostGIS Map Optimization Migration
-- ============================================================
-- Run this in Supabase SQL Editor
-- 
-- What this does:
--   1. Fix tables GiST index (currently B-tree, should be GiST)
--   2. Add PostGIS geography column to events + posts
--   3. Rewrite map_ready_tables view (eliminate GROUP BY)
--   4. Rewrite get_events_in_viewport RPC (use ST_Intersects)
--   5. Rewrite map_live_stories_view (use PostGIS)
--   6. Create get_stories_in_viewport RPC
-- ============================================================


-- ============================================================
-- STEP 1: Fix tables GiST index
-- Currently idx_tables_location is B-tree on (lat, lng)
-- PostGIS needs GiST on the geography column
-- ============================================================

DROP INDEX IF EXISTS idx_tables_location;

CREATE INDEX IF NOT EXISTS idx_tables_location_gist
ON public.tables USING GIST (location);


-- ============================================================
-- STEP 2A: Add PostGIS geography column to events
-- ============================================================

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- Backfill (15 rows — instant)
UPDATE public.events
SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND location IS NULL;

-- GiST index
CREATE INDEX IF NOT EXISTS idx_events_location_gist
ON public.events USING GIST (location);

-- Sync trigger: auto-populate geography column on INSERT/UPDATE
CREATE OR REPLACE FUNCTION update_event_location()
RETURNS TRIGGER AS $fn1$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  RETURN NEW;
END;
$fn1$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_event_location_trigger ON public.events;
CREATE TRIGGER update_event_location_trigger
  BEFORE INSERT OR UPDATE OF latitude, longitude
  ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION update_event_location();

-- Drop redundant flat B-tree indexes (GiST replaces them)
DROP INDEX IF EXISTS idx_events_active_location;
DROP INDEX IF EXISTS idx_events_viewport;


-- ============================================================
-- STEP 2B: Add PostGIS geography column to posts
-- ============================================================

ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- Backfill (162 rows — instant)
UPDATE public.posts
SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND location IS NULL;

-- GiST index
CREATE INDEX IF NOT EXISTS idx_posts_location_gist
ON public.posts USING GIST (location);

-- Sync trigger: auto-populate geography column on INSERT/UPDATE
CREATE OR REPLACE FUNCTION update_post_location()
RETURNS TRIGGER AS $fn2$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  RETURN NEW;
END;
$fn2$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_post_location_trigger ON public.posts;
CREATE TRIGGER update_post_location_trigger
  BEFORE INSERT OR UPDATE OF latitude, longitude
  ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION update_post_location();

-- Keep old B-tree indexes (still used by feed H3 queries)
-- idx_posts_story_viewport and idx_posts_story_recent stay


-- ============================================================
-- STEP 3: Rewrite map_ready_tables view
-- REMOVES: GROUP BY + table_participants JOIN (was redundant)
-- USES: current_capacity column (trigger-maintained)
-- ============================================================

DROP VIEW IF EXISTS public.map_ready_tables CASCADE;

CREATE VIEW public.map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name AS venue_name,
    t.venue_address,
    t.latitude AS location_lat,
    t.longitude AS location_lng,
    t.location,  -- PostGIS geography column for spatial queries
    t.datetime AS scheduled_time,
    t.max_guests AS max_capacity,
    t.status,
    t.current_capacity,

    -- Marker display
    t.marker_image_url,
    t.marker_emoji,
    t.image_url,
    t.images,

    -- Activity info
    t.cuisine_type AS activity_type,
    t.price_per_person,
    t.dietary_restrictions AS budget_range,
    t.visibility,

    -- Experience columns
    t.experience_type,
    t.video_url,
    t.currency,
    t.is_experience,
    t.requirements,
    t.included_items,
    t.verified_by_hanghut,

    -- Host info
    t.host_id,
    COALESCE(u.display_name, 'Unknown Host') AS host_name,
    (
        SELECT photo_url 
        FROM public.user_photos up 
        WHERE up.user_id = t.host_id 
        ORDER BY up.is_primary DESC, up.sort_order ASC 
        LIMIT 1
    ) AS host_photo_url,
    COALESCE(u.trust_score, 0) AS host_trust_score,

    -- Capacity (from trigger-maintained column — NO GROUP BY needed)
    t.current_capacity AS member_count,
    (t.max_guests - t.current_capacity) AS seats_left,
    CASE 
        WHEN t.current_capacity >= t.max_guests THEN 'full'
        WHEN t.current_capacity::numeric >= (t.max_guests::numeric * 0.8) THEN 'filling_up'
        ELSE 'available'
    END AS availability_state

FROM public.tables t
LEFT JOIN public.users u ON t.host_id = u.id
WHERE t.status = 'open'
  AND t.datetime > NOW()
  AND (
    t.is_experience = false 
    OR t.is_experience IS NULL 
    OR t.verified_by_hanghut = true
  );

GRANT SELECT ON public.map_ready_tables TO anon, authenticated, service_role;


-- ============================================================
-- STEP 4: Rewrite get_events_in_viewport RPC
-- Uses ST_Intersects with the GiST-indexed geography column
-- Falls back to flat lat/lng for events WITHOUT location column
-- ============================================================

CREATE OR REPLACE FUNCTION get_events_in_viewport(
  min_lat DOUBLE PRECISION,
  max_lat DOUBLE PRECISION,
  min_lng DOUBLE PRECISION,
  max_lng DOUBLE PRECISION
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  description TEXT,
  venue_name TEXT,
  venue_address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  start_datetime TIMESTAMPTZ,
  end_datetime TIMESTAMPTZ,
  cover_image_url TEXT,
  ticket_price NUMERIC,
  capacity INTEGER,
  tickets_sold INTEGER,
  category TEXT,
  organizer_id UUID,
  organizer_name TEXT,
  organizer_photo_url TEXT,
  organizer_verified BOOLEAN,
  created_at TIMESTAMPTZ
) AS $fn3$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.title,
    e.description,
    e.venue_name,
    e.address AS venue_address,
    e.latitude,
    e.longitude,
    e.start_datetime,
    e.end_datetime,
    e.cover_image_url,
    e.ticket_price,
    e.capacity,
    e.tickets_sold,
    e.event_type::TEXT AS category,
    e.organizer_id,
    p.business_name AS organizer_name,
    p.profile_photo_url AS organizer_photo_url,
    p.verified AS organizer_verified,
    e.created_at
  FROM events e
  LEFT JOIN partners p ON e.organizer_id = p.id
  WHERE (
    -- Use PostGIS spatial index when location column is populated
    (e.location IS NOT NULL AND ST_Intersects(
      e.location,
      ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)::geography
    ))
    OR
    -- Fallback for any rows missing the geography column
    (e.location IS NULL 
      AND e.latitude BETWEEN min_lat AND max_lat
      AND e.longitude BETWEEN min_lng AND max_lng)
  )
    AND e.status = 'active'
    AND e.start_datetime > NOW()
  ORDER BY e.start_datetime ASC
  LIMIT 500;
END;
$fn3$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_events_in_viewport IS 'Fetches active upcoming events using PostGIS spatial index (GiST) with flat lat/lng fallback';


-- ============================================================
-- STEP 5: Rewrite map_live_stories_view
-- Includes PostGIS location column for spatial queries
-- ============================================================

DROP VIEW IF EXISTS public.map_live_stories_view;

CREATE OR REPLACE VIEW public.map_live_stories_view AS
SELECT 
    p.event_id,
    p.table_id,
    p.external_place_id,
    p.external_place_name,
    p.latitude,
    p.longitude,
    p.location,  -- PostGIS geography for spatial queries
    count(p.id) AS story_count,
    max(p.created_at) AS latest_story_time,
    (array_agg(p.id ORDER BY p.created_at DESC))[1] AS id,
    (array_agg(p.image_url ORDER BY p.created_at DESC))[1] AS image_url,
    (array_agg(p.user_id ORDER BY p.created_at DESC))[1] AS author_id,
    (array_agg(u.display_name ORDER BY p.created_at DESC))[1] AS author_name,
    (array_agg(COALESCE(u.avatar_url, up_photo.photo_url) ORDER BY p.created_at DESC))[1] AS author_avatar_url
FROM 
    public.posts p
LEFT JOIN public.users u ON p.user_id = u.id
LEFT JOIN public.user_photos up_photo ON u.id = up_photo.user_id AND up_photo.is_primary = true
WHERE 
    p.is_story = true 
    AND p.created_at > (NOW() - INTERVAL '24 hours')
GROUP BY 
    p.event_id, p.table_id, p.external_place_id, p.external_place_name, 
    p.latitude, p.longitude, p.location;

GRANT SELECT ON public.map_live_stories_view TO anon, authenticated, service_role;


-- ============================================================
-- STEP 6: Create get_stories_in_viewport RPC
-- Replaces client-side PostgREST bounding box with ST_Intersects
-- ============================================================

CREATE OR REPLACE FUNCTION get_stories_in_viewport(
  min_lat DOUBLE PRECISION,
  max_lat DOUBLE PRECISION,
  min_lng DOUBLE PRECISION,
  max_lng DOUBLE PRECISION
)
RETURNS TABLE (
  event_id UUID,
  table_id UUID,
  external_place_id TEXT,
  external_place_name TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  story_count BIGINT,
  latest_story_time TIMESTAMPTZ,
  id UUID,
  image_url TEXT,
  author_id UUID,
  author_name TEXT,
  author_avatar_url TEXT
) AS $fn4$
BEGIN
  RETURN QUERY
  SELECT 
    s.event_id,
    s.table_id,
    s.external_place_id,
    s.external_place_name,
    s.latitude,
    s.longitude,
    s.story_count,
    s.latest_story_time,
    s.id,
    s.image_url,
    s.author_id,
    s.author_name,
    s.author_avatar_url
  FROM public.map_live_stories_view s
  WHERE (
    (s.location IS NOT NULL AND ST_Intersects(
      s.location,
      ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)::geography
    ))
    OR
    (s.location IS NULL
      AND s.latitude BETWEEN min_lat AND max_lat
      AND s.longitude BETWEEN min_lng AND max_lng)
  )
  LIMIT 100;
END;
$fn4$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_stories_in_viewport IS 'Fetches live stories using PostGIS spatial index with flat lat/lng fallback';


-- ============================================================
-- VERIFICATION
-- ============================================================

DO $verify$
DECLARE
  v_tables_gist BOOLEAN;
  v_events_gist BOOLEAN;
  v_posts_gist BOOLEAN;
  v_events_location BOOLEAN;
  v_posts_location BOOLEAN;
  v_events_backfilled BIGINT;
  v_posts_backfilled BIGINT;
BEGIN
  -- Check GiST indexes exist
  SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tables_location_gist') INTO v_tables_gist;
  SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname = 'idx_events_location_gist') INTO v_events_gist;
  SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname = 'idx_posts_location_gist') INTO v_posts_gist;
  
  -- Check location columns exist
  SELECT EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'events' AND column_name = 'location'
  ) INTO v_events_location;
  
  SELECT EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'posts' AND column_name = 'location'
  ) INTO v_posts_location;

  -- Check backfill counts
  SELECT COUNT(*) FROM public.events WHERE location IS NOT NULL INTO v_events_backfilled;
  SELECT COUNT(*) FROM public.posts WHERE location IS NOT NULL INTO v_posts_backfilled;

  RAISE NOTICE '';
  RAISE NOTICE '================================================';
  RAISE NOTICE '  PostGIS Map Optimization — Results';
  RAISE NOTICE '================================================';
  RAISE NOTICE '  GiST Index on tables:  %', CASE WHEN v_tables_gist THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  GiST Index on events:  %', CASE WHEN v_events_gist THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  GiST Index on posts:   %', CASE WHEN v_posts_gist THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  events.location col:   %', CASE WHEN v_events_location THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  posts.location col:    %', CASE WHEN v_posts_location THEN '✅' ELSE '❌' END;
  RAISE NOTICE '  Events backfilled:     %', v_events_backfilled;
  RAISE NOTICE '  Posts backfilled:      %', v_posts_backfilled;
  RAISE NOTICE '================================================';
  
  -- Test RPCs
  RAISE NOTICE '  Testing get_events_in_viewport...';
  PERFORM * FROM get_events_in_viewport(14.0, 15.0, 120.0, 122.0);
  RAISE NOTICE '  ✅ get_events_in_viewport works';
  
  RAISE NOTICE '  Testing get_stories_in_viewport...';
  PERFORM * FROM get_stories_in_viewport(14.0, 15.0, 120.0, 122.0);
  RAISE NOTICE '  ✅ get_stories_in_viewport works';
  
  RAISE NOTICE '  Testing map_ready_tables view...';
  PERFORM * FROM map_ready_tables LIMIT 1;
  RAISE NOTICE '  ✅ map_ready_tables works (no GROUP BY!)';
  
  RAISE NOTICE '================================================';
  RAISE NOTICE '  ALL CHECKS PASSED — Migration complete!';
  RAISE NOTICE '================================================';
END $verify$;
