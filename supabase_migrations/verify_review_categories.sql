-- ============================================================================
-- Verify: experience_reviews table + trigger + RLS
-- Run this in the Supabase SQL Editor to confirm everything is set up.
-- ============================================================================

-- 1. Table exists and has expected columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'experience_reviews'
ORDER BY ordinal_position;

-- 2. Unique constraint exists
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'experience_reviews' AND table_schema = 'public';

-- 3. Trigger exists
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'experience_reviews' AND trigger_schema = 'public';

-- 4. RLS is enabled + policies exist
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'experience_reviews';

-- 5. Trigger function exists
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name = 'recompute_host_trust_score' AND routine_schema = 'public';
