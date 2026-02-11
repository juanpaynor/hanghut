-- RPC to get count of active users currently in the Philippines
-- Philippines geographic bounds: ~4.5°N to 21°N, ~116°E to 127°E
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
      last_active_at > (now() - interval '10 minutes')
      AND current_lat IS NOT NULL
      AND current_lng IS NOT NULL
      AND current_lat BETWEEN 4.5 AND 21.0  -- Philippines latitude range
      AND current_lng BETWEEN 116.0 AND 127.0  -- Philippines longitude range
      AND (status = 'active' OR status IS NULL)
  );
END;
$$;
