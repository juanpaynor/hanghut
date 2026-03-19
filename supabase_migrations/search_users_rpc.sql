-- Search users RPC — single query, no N+1
-- Returns user info with avatar in one shot using a lateral join

CREATE OR REPLACE FUNCTION search_users(
  p_query TEXT,
  p_limit INT DEFAULT 20,
  p_exclude_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  username TEXT,
  avatar_url TEXT,
  bio TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id,
    u.display_name,
    u.username,
    COALESCE(
      (SELECT up.photo_url FROM public.user_photos up 
       WHERE up.user_id = u.id AND up.is_primary = true 
       LIMIT 1),
      (SELECT up.photo_url FROM public.user_photos up 
       WHERE up.user_id = u.id 
       ORDER BY up.id ASC 
       LIMIT 1)
    ) AS avatar_url,
    u.bio
  FROM public.users u
  WHERE 
    (p_exclude_user_id IS NULL OR u.id != p_exclude_user_id)
    AND (
      u.display_name ILIKE '%' || p_query || '%'
      OR u.username ILIKE '%' || p_query || '%'
    )
  ORDER BY 
    -- Exact username match first
    CASE WHEN LOWER(u.username) = LOWER(p_query) THEN 0 ELSE 1 END,
    -- Then prefix matches
    CASE WHEN u.username ILIKE p_query || '%' THEN 0 ELSE 1 END,
    CASE WHEN u.display_name ILIKE p_query || '%' THEN 0 ELSE 1 END,
    -- Then everything else by name
    u.display_name
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add trigram extension for future fuzzy search optimization
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX IF NOT EXISTS idx_users_display_name_trgm ON public.users USING gin (display_name gin_trgm_ops);
-- CREATE INDEX IF NOT EXISTS idx_users_username_trgm ON public.users USING gin (username gin_trgm_ops);
