-- Fix get_main_feed RPC to show posts without H3 cells
-- This allows posts created without location to appear in everyone's feed

-- Drop existing function to allow return type change
DROP FUNCTION IF EXISTS get_main_feed(integer, integer, double precision, double precision, text[]);

CREATE OR REPLACE FUNCTION get_main_feed(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0,
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
    
    like_count INT,
    comment_count INT,
    is_liked BOOLEAN
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
                 (SELECT photo_url FROM user_photos up WHERE up.user_id = u.id ORDER BY is_primary DESC LIMIT 1)
            )
        ) as user_data,
        
        -- Stats
        (SELECT COUNT(*)::INT FROM post_likes pl WHERE pl.post_id = p.id) as like_count,
        (SELECT COUNT(*)::INT FROM comments c WHERE c.post_id = p.id) as comment_count,
        
        -- Is Liked
        CASE 
            WHEN v_current_user_id IS NULL THEN FALSE
            ELSE EXISTS (SELECT 1 FROM post_likes pl WHERE pl.post_id = p.id AND pl.user_id = v_current_user_id)
        END as is_liked
        
    FROM posts p
    JOIN users u ON p.user_id = u.id
    WHERE 
        -- Location Filter: Show posts in user's area OR posts without location (global)
        (
            p_h3_cells IS NULL 
            OR 
            p.h3_cell = ANY(p_h3_cells)
            OR
            p.h3_cell IS NULL  -- ADDED: Show posts without H3 cell (global posts)
        )
        AND
        -- Visibility Filter
        (
            (v_current_user_id IS NOT NULL AND p.user_id = v_current_user_id)
            OR
            (p.visibility = 'public')
            OR
            (
                p.visibility = 'followers' 
                AND 
                p.user_id = ANY(v_following_ids)
            )
        )
    ORDER BY p.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;
