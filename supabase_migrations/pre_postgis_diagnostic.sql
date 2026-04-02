-- ============================================================
-- PRE-MIGRATION DIAGNOSTIC: Run this FIRST in Supabase SQL Editor
-- This checks what already exists before we make changes
-- ============================================================

-- 1. Check if PostGIS extension is enabled
SELECT extname, extversion 
FROM pg_extension 
WHERE extname IN ('postgis', 'h3', 'pg_cron');

-- 2. Check if `location` GEOGRAPHY column exists on each table
SELECT 
    table_name, 
    column_name, 
    data_type, 
    udt_name
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND column_name = 'location'
  AND table_name IN ('tables', 'events', 'posts')
ORDER BY table_name;

-- 3. Check existing spatial indexes (GiST)
SELECT 
    indexname, 
    tablename, 
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND (
    indexname LIKE '%location%' 
    OR indexname LIKE '%viewport%' 
    OR indexname LIKE '%story%' 
    OR indexname LIKE '%h3%'
    OR indexname LIKE '%lat%'
    OR indexname LIKE '%lng%'
    OR indexname LIKE '%gist%'
  )
ORDER BY tablename, indexname;

-- 4. Check if current_capacity column exists on tables
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'tables' 
  AND column_name = 'current_capacity';

-- 5. Check existing triggers related to location/capacity
SELECT 
    trigger_name, 
    event_object_table, 
    action_statement
FROM information_schema.triggers 
WHERE trigger_schema = 'public' 
  AND (
    trigger_name LIKE '%location%' 
    OR trigger_name LIKE '%capacity%'
  )
ORDER BY event_object_table;

-- 6. Check current map_ready_tables view definition
SELECT pg_get_viewdef('public.map_ready_tables'::regclass, true) AS view_definition;

-- 7. Check current map_live_stories_view definition
SELECT pg_get_viewdef('public.map_live_stories_view'::regclass, true) AS view_definition;

-- 8. Check get_events_in_viewport function signature
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'get_events_in_viewport';

-- 9. Row counts (to estimate migration time)
SELECT 'tables' AS table_name, COUNT(*) AS row_count FROM public.tables
UNION ALL
SELECT 'events', COUNT(*) FROM public.events
UNION ALL
SELECT 'posts', COUNT(*) FROM public.posts
UNION ALL
SELECT 'posts (stories)', COUNT(*) FROM public.posts WHERE is_story = true
UNION ALL
SELECT 'table_participants', COUNT(*) FROM public.table_participants;

-- 10. Check if location column on tables is populated
SELECT 
    COUNT(*) AS total_tables,
    COUNT(location) AS tables_with_location,
    COUNT(*) - COUNT(location) AS tables_missing_location
FROM public.tables;

-- ============================================================
-- EXPECTED RESULTS:
-- 1. postgis should show as installed
-- 2. `location` should exist on `tables` but NOT on `events`/`posts`
-- 3. idx_tables_location (GiST) should exist
-- 4. current_capacity should exist on tables
-- 5. update_table_location_trigger should exist
-- 6-8. Current view/function definitions for reference
-- 9. Row counts tell us how long backfill will take
-- 10. How many tables already have the PostGIS column populated
-- ============================================================
