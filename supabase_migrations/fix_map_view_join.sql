-- CRITICAL FIX: Recreate map_ready_tables view with ALL required fields
-- Issues fixed:
-- 1. Missing image_url field (causing GIF to disappear)
-- 2. Missing current_capacity field
-- 3. Ensure view works even when public.users profile is missing

DROP VIEW IF EXISTS public.map_ready_tables CASCADE;

CREATE VIEW public.map_ready_tables WITH (security_invoker = true) AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name as venue_name,
    t.venue_address,  -- ADDED
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.current_capacity,  -- ADDED: Current capacity from tables
    t.status,
    t.marker_image_url,
    t.marker_emoji,
    t.image_url,  -- CRITICAL FIX: Include the GIF/image URL
    t.cuisine_type as activity_type,  -- Renamed for consistency
    t.price_per_person,
    t.dietary_restrictions as budget_range,  -- Mapped for compatibility
    
    -- Host info
    t.host_id,
    COALESCE(u.display_name, 'Unknown Host') as host_name,
    (
        SELECT photo_url 
        FROM public.user_photos up 
        WHERE up.user_id = t.host_id  -- Use host_id directly
        ORDER BY up.is_primary DESC, up.sort_order ASC 
        LIMIT 1
    ) as host_photo_url,
    COALESCE(u.trust_score, 0) as host_trust_score,
    
    -- Capacity info from table_participants
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
  AND t.datetime > NOW()
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- Grant permissions
GRANT SELECT ON public.map_ready_tables TO anon, authenticated, service_role;
