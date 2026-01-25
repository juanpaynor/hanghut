-- Add location tracking columns to users table
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;

-- Create bbox index for fast viewport queries
CREATE INDEX IF NOT EXISTS idx_users_location_bbox 
  ON users (current_lat, current_lng)
  WHERE current_lat IS NOT NULL AND current_lng IS NOT NULL;

-- Function to update user's current location (called once per 24h from app)
CREATE OR REPLACE FUNCTION update_user_location(
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION
)
RETURNS void AS $$
BEGIN
  UPDATE users
  SET 
    current_lat = lat,
    current_lng = lng,
    location_updated_at = NOW()
  WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get active users within a viewport
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
        SELECT jsonb_agg(jsonb_build_object('photo_url', p.photo_url))
        FROM user_photos p
        WHERE p.user_id = u.id
        ORDER BY p.is_primary DESC, p.display_order
        LIMIT 1
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
