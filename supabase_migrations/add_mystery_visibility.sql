-- ============================================================
-- Mystery Tables: Add 'mystery' visibility type
-- ============================================================
-- Adds 'mystery' as a third visibility option for tables.
-- Mystery tables are hidden on the map until a user activates
-- the isochrone walking-distance pulse near them.
-- ============================================================

-- 1. Drop existing CHECK constraint and add new one with 'mystery'
ALTER TABLE public.tables
  DROP CONSTRAINT IF EXISTS tables_visibility_check;

ALTER TABLE public.tables
  ADD CONSTRAINT tables_visibility_check
  CHECK (visibility = ANY (ARRAY['public', 'followers_only', 'mystery']));

-- 2. Recreate map_ready_tables view to expose 'visibility' column
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
    t.status,
    t.current_capacity, 
    t.marker_image_url,
    t.marker_emoji,
    t.image_url,
    t.cuisine_type as activity_type,
    t.price_per_person,
    t.dietary_restrictions as budget_range,
    t.visibility,  -- NEW: Expose visibility for client-side mystery filtering
    
    -- Experience Columns
    t.experience_type,
    t.images,
    t.video_url,
    t.currency,
    t.is_experience,
    t.requirements,
    t.included_items,
    t.verified_by_hanghut,

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
    
    -- Capacity info (Calculated)
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
  -- Hide unverified experiences from the map
  AND (t.is_experience = false OR t.is_experience IS NULL OR t.verified_by_hanghut = true)
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- Grant permissions
GRANT SELECT ON public.map_ready_tables TO anon, authenticated, service_role;
