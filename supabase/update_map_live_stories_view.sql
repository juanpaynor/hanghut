-- Drop the existing view
DROP VIEW IF EXISTS public.map_live_stories_view;

-- Recreate with the latest image_url and author_avatar_url
CREATE OR REPLACE VIEW public.map_live_stories_view AS
SELECT 
    p.event_id,
    p.table_id,
    p.external_place_id,
    p.external_place_name,
    p.latitude,
    p.longitude,
    count(p.id) as story_count,
    max(p.created_at) as latest_story_time,
    -- Get the ID of the most recent story at this location to use as a unique marker key
    (array_agg(p.id ORDER BY p.created_at DESC))[1] as id,
    -- Get the image URL of the most recent story at this location
    (array_agg(p.image_url ORDER BY p.created_at DESC))[1] as image_url,
    -- Get the User ID of the most recent story at this location
    (array_agg(p.user_id ORDER BY p.created_at DESC))[1] as author_id,
    -- Get the User name of the most recent story at this location
    (array_agg(u.display_name ORDER BY p.created_at DESC))[1] as author_name,
    -- Get the User avatar URL of the most recent story at this location
    (array_agg(COALESCE(u.avatar_url, up_photo.photo_url) ORDER BY p.created_at DESC))[1] as author_avatar_url
FROM 
    public.posts p
LEFT JOIN public.users u ON p.user_id = u.id
LEFT JOIN public.user_photos up_photo ON u.id = up_photo.user_id AND up_photo.is_primary = true
WHERE 
    p.is_story = true 
    AND p.created_at > (NOW() - INTERVAL '24 hours')
GROUP BY 
    p.event_id, p.table_id, p.external_place_id, p.external_place_name, p.latitude, p.longitude;
