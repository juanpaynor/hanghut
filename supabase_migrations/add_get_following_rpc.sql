-- Function to get list of users I follow
CREATE OR REPLACE FUNCTION get_following_ids(user_id UUID)
RETURNS TABLE (following_id UUID) AS $$
BEGIN
  RETURN QUERY
  SELECT f.following_id
  FROM follows f
  WHERE f.follower_id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
