-- DIAGNOSTIC VIEW: Debug Map Visibility
-- Run this to understand why tables are not showing up in the map view.
-- It shows ALL tables and flags potential reasons for them being hidden.

DROP VIEW IF EXISTS public.debug_map_tables;

CREATE VIEW public.debug_map_tables AS
SELECT 
    t.id,
    t.title,
    t.host_id,
    t.status,
    t.datetime,
    
    -- Check 1: Is the status 'open'?
    (t.status = 'open') as is_open,
    
    -- Check 2: Is the date in the future?
    (t.datetime > NOW()) as is_future_date,
    
    -- Check 3: Does the host exist in public.users?
    (u.id IS NOT NULL) as host_profile_exists,
    
    -- Check 4: Does the host have a primary photo?
    (EXISTS (SELECT 1 FROM public.user_photos up WHERE up.user_id = t.host_id AND up.is_primary = true)) as host_has_photo,
    
    -- Check 5: Is there a mismatch between auth and public?
    -- (We can't querying auth.users directly easily in a view, but we can infer from u.id missing)
    
    u.display_name as host_name
    
FROM public.tables t
LEFT JOIN public.users u ON t.host_id = u.id;

-- Grant access so you can query it from the dashboard/client
GRANT SELECT ON public.debug_map_tables TO anon, authenticated, service_role;
