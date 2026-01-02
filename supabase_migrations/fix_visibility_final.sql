-- FINAL FIX for Visibility Issues
-- 1. Drop the view to recreate it with correct security options
DROP VIEW IF EXISTS public.map_ready_tables;

-- 2. Ensure RLS policies are permissive for public viewing
-- Users table: Allow everyone to view basic profile info
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.users;
CREATE POLICY "Public profiles are viewable by everyone" ON public.users
  FOR SELECT USING (true);

-- User Photos: Allow everyone to view photos
ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User photos are viewable by everyone" ON public.user_photos;
CREATE POLICY "User photos are viewable by everyone" ON public.user_photos
  FOR SELECT USING (true);

-- Tables: Allow everyone to view open tables
ALTER TABLE public.tables ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view open tables" ON public.tables;
CREATE POLICY "Anyone can view open tables" ON public.tables
  FOR SELECT USING (true);

-- 3. Recreate the view with security_invoker = true
-- This ensures the view respects the RLS policies of the user querying it
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
  AND t.datetime > NOW()
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- 4. Grant explicit permissions (Security Invoker handles RLS, grants handle access to view itself)
GRANT SELECT ON public.map_ready_tables TO anon;
GRANT SELECT ON public.map_ready_tables TO authenticated;
GRANT SELECT ON public.map_ready_tables TO service_role;
