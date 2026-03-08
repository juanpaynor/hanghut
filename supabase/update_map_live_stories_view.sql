-- Drop the existing view
DROP VIEW IF EXISTS public.map_live_stories_view;

-- Recreate with the latest image_url
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
    -- Get the image URL of the most recent story at this location
    (array_agg(p.image_url ORDER BY p.created_at DESC))[1] as image_url,
    -- Get the User ID of the most recent story at this location
    (array_agg(p.user_id ORDER BY p.created_at DESC))[1] as author_id
FROM 
    public.posts p
WHERE 
    p.is_story = true 
    AND p.created_at > (NOW() - INTERVAL '24 hours')
GROUP BY 
    p.event_id, p.table_id, p.external_place_id, p.external_place_name, p.latitude, p.longitude;
