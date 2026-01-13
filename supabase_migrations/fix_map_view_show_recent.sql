-- Fix map_ready_tables view to show recent past tables (last 24 hours)
-- This allows users to see tables that just happened

DROP VIEW IF EXISTS public.map_ready_tables;

CREATE VIEW public.map_ready_tables WITH (security_invoker = true) AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name as venue_name,
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.status,
    t.marker_image_url,
    t.marker_emoji,
    t.cuisine_type,
    t.price_per_person,
    t.dietary_restrictions,
    
    -- Host info
    t.host_id,
    u.display_name as host_name,
    (
        SELECT photo_url 
        FROM public.user_photos up 
        WHERE up.user_id = u.id 
        ORDER BY up.is_primary DESC, up.sort_order ASC 
        LIMIT 1
    ) as host_photo_url,
    COALESCE(u.trust_score, 0) as host_trust_score,
    
    -- Capacity info
    COUNT(tp.id) FILTER (WHERE tp.status IN ('confirmed', 'pending')) as member_count,
    (t.max_guests - COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed')) as seats_left,
    CASE 
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= t.max_guests THEN 'full'
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= (t.max_guests * 0.8) THEN 'filling_up'
        ELSE 'available'
    END as availability_state
    
FROM public.tables t
LEFT JOIN public.users u ON t.host_id = u.id
LEFT JOIN public.table_participants tp ON t.id = tp.table_id
WHERE t.status = 'open'
  AND t.datetime > NOW() - INTERVAL '24 hours'  -- Changed: Show tables from last 24 hours
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- Grant explicit permissions
GRANT SELECT ON public.map_ready_tables TO anon;
GRANT SELECT ON public.map_ready_tables TO authenticated;
GRANT SELECT ON public.map_ready_tables TO service_role;
