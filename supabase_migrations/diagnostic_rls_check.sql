-- Diagnostic queries to check RLS policies and data visibility

-- 1. Check if RLS is enabled on tables
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('tables', 'posts', 'users');

-- 2. Check RLS policies for tables table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'tables';

-- 3. Check RLS policies for posts table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'posts';

-- 4. Count total tables (should show all)
SELECT COUNT(*) as total_tables FROM public.tables;

-- 5. Count total posts (should show all)
SELECT COUNT(*) as total_posts FROM public.posts;

-- 6. Sample query - get recent tables (this is what the app does)
SELECT id, title, location_name, latitude, longitude, status, host_id
FROM public.tables
WHERE status = 'open'
ORDER BY created_at DESC
LIMIT 10;

-- 7. Sample query - get recent posts
SELECT id, content, user_id, created_at
FROM public.posts
ORDER BY created_at DESC
LIMIT 10;
