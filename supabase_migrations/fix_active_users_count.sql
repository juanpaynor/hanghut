-- Fix active users count & list to not miss users without location data
-- 
-- Problem: Both RPCs required current_lat/current_lng to be non-NULL
-- AND within Philippines bounds. But location only updates every 24h, so many
-- active users had NULL coordinates and were excluded.
--
-- Fix: Remove the strict geo-filter since the app is PH-only for now.
-- Widen the window from 10 to 15 minutes to account for the 5-min heartbeat.

-- 1. Fix the COUNT RPC (used by the map pill)
CREATE OR REPLACE FUNCTION get_active_users_philippines_count()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT count(*) 
    FROM users 
    WHERE 
      last_active_at > (now() - interval '15 minutes')
      AND (status = 'active' OR status IS NULL)
  );
END;
$$;

-- 2. Fix the LIST RPC (used by the active users bottom sheet)
CREATE OR REPLACE FUNCTION get_active_users_philippines(
  page_size INT DEFAULT 20,
  page_number INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  avatar_url TEXT,
  last_active_at TIMESTAMPTZ,
  user_photos JSONB,
  current_lat DOUBLE PRECISION,
  current_lng DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id,
    u.display_name,
    u.avatar_url,
    u.last_active_at,
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('photo_url', sub.photo_url))
        FROM (
          SELECT p.photo_url
          FROM user_photos p
          WHERE p.user_id = u.id
          ORDER BY p.is_primary DESC NULLS LAST, p.display_order
          LIMIT 1
        ) sub
      ),
      '[]'::jsonb
    ) as user_photos,
    u.current_lat,
    u.current_lng
  FROM users u
  WHERE 
    u.last_active_at > NOW() - INTERVAL '15 minutes'
    AND (u.status = 'active' OR u.status IS NULL)
  ORDER BY u.last_active_at DESC
  LIMIT page_size
  OFFSET (page_number * page_size);
END;
$$ LANGUAGE plpgsql;
