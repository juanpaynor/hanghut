-- EMERGENCY CHECK: Count raw table rows
-- Run this to see if data even exists.

SELECT count(*) as total_tables FROM public.tables;

-- If this returns > 0, then RLS is hiding them.
-- If this returns 0, your data is GONE or you are connected to wrong DB.

-- Also check RLS status
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'tables';
