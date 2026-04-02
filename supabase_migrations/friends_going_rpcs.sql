-- ============================================
-- Friends Going Feature: RPC Functions
-- ============================================
-- These functions return friends (people the current user follows)
-- who have joined a given event, table, or experience.
-- Respects the hide_activity_from_friends privacy setting.
-- Profile pictures come from user_photos (primary photo).

-- Drop existing functions first (return type changed from avatar_url to photo_url)
DROP FUNCTION IF EXISTS get_friends_going_to_event(UUID);
DROP FUNCTION IF EXISTS get_friends_at_table(UUID);
DROP FUNCTION IF EXISTS get_friends_in_experience(UUID);

-- ============================================
-- 1. Friends going to an EVENT (via tickets)
-- ============================================
CREATE OR REPLACE FUNCTION get_friends_going_to_event(p_event_id UUID)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  photo_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT u.id, u.display_name,
    (SELECT up.photo_url FROM user_photos up WHERE up.user_id = u.id AND up.is_primary = true LIMIT 1)
  FROM tickets t
  JOIN follows f ON f.following_id = t.user_id
  JOIN users u ON u.id = t.user_id
  WHERE t.event_id = p_event_id
    AND t.status = 'valid'
    AND f.follower_id = auth.uid()
    AND t.user_id != auth.uid()
    AND u.hide_activity_from_friends IS NOT TRUE
  ORDER BY u.display_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 2. Friends at a TABLE/ACTIVITY (via table_members)
-- ============================================
CREATE OR REPLACE FUNCTION get_friends_at_table(p_table_id UUID)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  photo_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT u.id, u.display_name,
    (SELECT up.photo_url FROM user_photos up WHERE up.user_id = u.id AND up.is_primary = true LIMIT 1)
  FROM table_members tm
  JOIN follows f ON f.following_id = tm.user_id
  JOIN users u ON u.id = tm.user_id
  WHERE tm.table_id = p_table_id
    AND tm.status = 'active'
    AND f.follower_id = auth.uid()
    AND tm.user_id != auth.uid()
    AND u.hide_activity_from_friends IS NOT TRUE
  ORDER BY u.display_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. Friends booked an EXPERIENCE (via experience_purchase_intents)
-- ============================================
CREATE OR REPLACE FUNCTION get_friends_in_experience(p_table_id UUID)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  photo_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT u.id, u.display_name,
    (SELECT up.photo_url FROM user_photos up WHERE up.user_id = u.id AND up.is_primary = true LIMIT 1)
  FROM experience_purchase_intents epi
  JOIN follows f ON f.following_id = epi.user_id
  JOIN users u ON u.id = epi.user_id
  WHERE epi.table_id = p_table_id
    AND epi.status = 'completed'
    AND f.follower_id = auth.uid()
    AND epi.user_id != auth.uid()
    AND u.hide_activity_from_friends IS NOT TRUE
  ORDER BY u.display_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_friends_going_to_event(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_friends_at_table(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_friends_in_experience(UUID) TO authenticated;
