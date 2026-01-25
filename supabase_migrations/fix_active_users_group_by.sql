-- Fix GROUP BY error in get_active_users and get_active_users_in_viewport
-- The issue: p.is_primary in ORDER BY causes "column must appear in GROUP BY clause" error
-- Solution: Use array_agg with proper ordering instead of jsonb_agg in subquery

-- Drop existing functions first to avoid return type conflicts
DROP FUNCTION IF EXISTS get_active_users(integer, integer);
DROP FUNCTION IF EXISTS get_active_users_in_viewport(double precision, double precision, double precision, double precision, integer, integer);

-- Fix get_active_users function
CREATE OR REPLACE FUNCTION get_active_users(
  page_size INT DEFAULT 20,
  page_number INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  avatar_url TEXT,
  last_active_at TIMESTAMPTZ,
  user_photos JSONB
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
    ) as user_photos
  FROM users u
  WHERE 
    u.last_active_at > NOW() - INTERVAL '10 minutes'
    AND (u.status = 'active' OR u.status IS NULL)
  ORDER BY u.last_active_at DESC
  LIMIT page_size
  OFFSET (page_number * page_size);
END;
$$ LANGUAGE plpgsql;

-- Fix get_active_users_in_viewport function
CREATE OR REPLACE FUNCTION get_active_users_in_viewport(
  min_lat DOUBLE PRECISION,
  max_lat DOUBLE PRECISION,
  min_lng DOUBLE PRECISION,
  max_lng DOUBLE PRECISION,
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
    u.last_active_at > NOW() - INTERVAL '10 minutes'
    AND u.current_lat IS NOT NULL
    AND u.current_lng IS NOT NULL
    -- Viewport filter (uses bbox index - very fast)
    AND u.current_lat BETWEEN min_lat AND max_lat
    AND u.current_lng BETWEEN min_lng AND max_lng
    AND (u.status = 'active' OR u.status IS NULL)
  ORDER BY u.last_active_at DESC
  LIMIT page_size
  OFFSET (page_number * page_size);
END;
$$ LANGUAGE plpgsql;
