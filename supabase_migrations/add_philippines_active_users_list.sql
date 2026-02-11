-- Get active users in Philippines for bottom sheet display
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
    u.last_active_at > NOW() - INTERVAL '10 minutes'
    -- Philippines geographic bounds
    AND u.current_lat BETWEEN 4.5 AND 21.0
    AND u.current_lng BETWEEN 116.0 AND 127.0
    AND (u.status = 'active' OR u.status IS NULL)
  ORDER BY u.last_active_at DESC
  LIMIT page_size
  OFFSET (page_number * page_size);
END;
$$ LANGUAGE plpgsql;
