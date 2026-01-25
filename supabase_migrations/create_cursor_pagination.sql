-- Phase 2: Cursor-Based Pagination RPC
-- This eliminates offset drift and provides constant-time performance

-- Drop existing function to allow return type change
DROP FUNCTION IF EXISTS get_main_feed_cursor(integer, timestamp without time zone, uuid, double precision, double precision, text[]);
DROP FUNCTION IF EXISTS get_main_feed_cursor(integer, timestamp with time zone, uuid, double precision, double precision, text[]);

CREATE OR REPLACE FUNCTION get_main_feed_cursor(
    p_limit INT DEFAULT 20,
    p_cursor TIMESTAMP DEFAULT NULL,
    p_cursor_id UUID DEFAULT NULL,
    p_user_lat FLOAT DEFAULT NULL,
    p_user_lng FLOAT DEFAULT NULL,
    p_h3_cells TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    image_url TEXT,
    image_urls TEXT[],
    gif_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    user_id UUID,
    post_type TEXT,
    metadata JSONB,
    visibility TEXT,
    city TEXT,
    h3_cell TEXT,
    latitude FLOAT,
    longitude FLOAT,
    
    user_data JSONB,
    
    like_count BIGINT,
    comment_count BIGINT,
    is_liked BOOLEAN,
    has_more BOOLEAN,
    next_cursor TIMESTAMP WITH TIME ZONE,
    next_cursor_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_following_ids UUID[];
BEGIN
    -- Cache following IDs
    SELECT COALESCE(array_agg(following_id), '{}') INTO v_following_ids
    FROM follows 
    WHERE follower_id = v_current_user_id;

    RETURN QUERY
    WITH filtered_posts AS (
        SELECT p.id, p.created_at
        FROM posts p
        WHERE 
            -- Cursor condition (for pagination)
            (
                p_cursor IS NULL OR
                p.created_at < p_cursor OR
                (p.created_at = p_cursor AND p.id < p_cursor_id)
            )
            AND
            -- Location Filter
            (
                p_h3_cells IS NULL 
                OR p.h3_cell = ANY(p_h3_cells)
                OR p.h3_cell IS NULL
            )
            AND
            -- Visibility Filter
            (
                (v_current_user_id IS NOT NULL AND p.user_id = v_current_user_id)
                OR (p.visibility = 'public')
                OR (p.visibility = 'followers' AND p.user_id = ANY(v_following_ids))
            )
        ORDER BY p.created_at DESC, p.id DESC
        LIMIT p_limit + 1  -- Fetch one extra to check has_more
    ),
    paginated_posts AS (
        SELECT 
            fp.id, 
            fp.created_at,
            ROW_NUMBER() OVER () as rn
        FROM filtered_posts fp
    )
    SELECT 
        p.id,
        p.content,
        p.image_url,
        p.image_urls::TEXT[],
        p.gif_url,
        p.created_at,
        p.user_id,
        p.post_type,
        p.metadata,
        p.visibility,
        p.city,
        p.h3_cell,
        p.latitude,
        p.longitude,
        
        -- User Object
        jsonb_build_object(
            'id', u.id,
            'display_name', u.display_name,
            'avatar_url', COALESCE(
                 u.avatar_url,
                 (SELECT photo_url FROM user_photos up 
                  WHERE up.user_id = u.id 
                  ORDER BY is_primary DESC LIMIT 1)
            )
        ) as user_data,
        
        -- Aggregated Stats (NO SUBQUERIES!)
        COALESCE(COUNT(DISTINCT pl.user_id), 0)::BIGINT as like_count,
        COALESCE(COUNT(DISTINCT c.id), 0)::BIGINT as comment_count,
        
        -- Is Liked Check
        CASE 
            WHEN v_current_user_id IS NULL THEN FALSE
            ELSE EXISTS (
                SELECT 1 FROM post_likes pll
                WHERE pll.post_id = p.id AND pll.user_id = v_current_user_id
            )
        END as is_liked,
        
        -- Has More flag
        (pp.rn > p_limit) as has_more,
        
        -- Next cursor values (for pagination)
        p.created_at as next_cursor,
        p.id as next_cursor_id
        
    FROM paginated_posts pp
    JOIN posts p ON pp.id = p.id
    JOIN users u ON p.user_id = u.id
    LEFT JOIN post_likes pl ON p.id = pl.post_id
    LEFT JOIN comments c ON p.id = c.post_id
    WHERE pp.rn <= p_limit  -- Only return requested limit
    GROUP BY p.id, u.id, u.display_name, u.avatar_url, pp.rn, p.created_at
    ORDER BY p.created_at DESC, p.id DESC;
END;
$$;

COMMENT ON FUNCTION get_main_feed_cursor IS 'Cursor-based pagination feed - constant performance, no duplicates with real-time updates';
