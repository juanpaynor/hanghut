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
  page_size int DEFAULT 20,
  page_number int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  display_name text,
  avatar_url text,
  user_photos json,
  last_active_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id, 
    u.display_name, 
    (
      SELECT photo_url 
      FROM user_photos up 
      WHERE up.user_id = u.id AND up.is_primary = true 
      LIMIT 1
    ) as avatar_url,
    (
      SELECT json_agg(json_build_object('photo_url', up.photo_url)) 
      FROM user_photos up 
      WHERE up.user_id = u.id
    ) as user_photos,
    u.last_active_at
  FROM users u
  WHERE u.last_active_at > (now() - interval '10 minutes')
  ORDER BY u.last_active_at DESC
  LIMIT page_size
  OFFSET page_number * page_size;
END;
$$;
