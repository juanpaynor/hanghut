-- Add last_active_at to users to track when user was last online
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP WITH TIME ZONE;

-- Create an index for efficient filtering on active users
CREATE INDEX IF NOT EXISTS idx_line_active_at ON users(last_active_at);

-- Create RPC function to get count of users active in the last 10 minutes
CREATE OR REPLACE FUNCTION get_active_user_count()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT count(*) 
    FROM users 
    WHERE last_active_at > (now() - interval '10 minutes')
  );
END;
$$;

-- Create RPC function to get list of active users with their primary photo
-- Supports pagination (page_size, page_number)
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
        SELECT jsonb_agg(jsonb_build_object('photo_url', p.photo_url))
        FROM user_photos p
        WHERE p.user_id = u.id
        ORDER BY p.is_primary DESC, p.display_order
        LIMIT 1
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
