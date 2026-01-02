-- ULTIMATE FIX: Recreate map_ready_tables as SECURITY DEFINER
-- Issue: security_invoker = true causes RLS to hide other users' tables.
-- Fix: Remove security_invoker (defaults to invoker=false, i.e., DEFINER).
-- Logic: Shows only FUTURE open tables (datetime > NOW()).

DROP VIEW IF EXISTS public.map_ready_tables CASCADE;

CREATE VIEW public.map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name as venue_name,
    t.venue_address,
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.current_capacity,
    t.status,
    t.marker_image_url,
    t.marker_emoji,
    t.image_url,
    t.cuisine_type as activity_type,
    t.price_per_person,
    t.dietary_restrictions as budget_range,
    
    -- Host info
    t.host_id,
    COALESCE(u.display_name, 'Unknown Host') as host_name,
    (
        SELECT photo_url 
        FROM public.user_photos up 
        WHERE up.user_id = t.host_id 
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
  AND t.datetime > NOW() -- Kept per user request (Important Feature)
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- Grant permissions explicitly
GRANT SELECT ON public.map_ready_tables TO anon, authenticated, service_role;
