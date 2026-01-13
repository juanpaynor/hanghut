-- Diagnostic query to check posts table structure and data

-- 1. Check posts table columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'posts'
ORDER BY ordinal_position;

-- 2. Check if posts have data
SELECT 
    id,
    user_id,
    content,
    created_at,
    visibility,
    h3_cell,
    city,
    post_type
FROM public.posts
ORDER BY created_at DESC
LIMIT 10;

-- 3. Count posts by visibility
SELECT visibility, COUNT(*) as count
FROM public.posts
GROUP BY visibility;

-- 4. Check if get_main_feed function exists
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'get_main_feed';
