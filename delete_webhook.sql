-- This drops the trigger that pushes to http_request_queue
DROP TRIGGER IF EXISTS "supabase_functions_table_members" ON public.table_members;
