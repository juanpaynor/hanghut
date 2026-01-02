-- Migration to update RPCs to use user_photos instead of users.avatar_url
-- This fixes missing avatars in "Also in Town" matches

-- 1. Update get_trip_matches to fetch from user_photos
CREATE OR REPLACE FUNCTION get_trip_matches(target_trip_id UUID)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    start_date DATE,
    end_date DATE,
    ingredients TEXT[],
    overlap_days INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    t_city TEXT;
    t_country TEXT;
    t_start DATE;
    t_end DATE;
    t_uid UUID;
BEGIN
    -- Get target trip details (O(1) lookup)
    SELECT ut.destination_city, ut.destination_country, ut.start_date, ut.end_date, ut.user_id
    INTO t_city, t_country, t_start, t_end, t_uid
    FROM user_trips ut
    WHERE ut.id = target_trip_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Find overlapping trips in same city (Indexed Scan)
    RETURN QUERY
    SELECT 
        u.id,
        u.display_name,
        (
            SELECT photo_url 
            FROM user_photos up 
            WHERE up.user_id = u.id 
            ORDER BY up.is_primary DESC, up.sort_order ASC 
            LIMIT 1
        ) as avatar_url,
        ut.start_date,
        ut.end_date,
        ut.interests,
        (LEAST(ut.end_date, t_end) - GREATEST(ut.start_date, t_start) + 1)::INT as overlap_days
    FROM user_trips ut
    JOIN users u ON ut.user_id = u.id
    WHERE 
        ut.destination_city = t_city
        AND ut.destination_country = t_country
        AND ut.id != target_trip_id -- Don't match self
        AND ut.user_id != t_uid     -- Don't match own other trips
        AND ut.status = 'upcoming'
        AND ut.start_date <= t_end
        AND ut.end_date >= t_start
    ORDER BY overlap_days DESC
    LIMIT 50;
END;
$$;
