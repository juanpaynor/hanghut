-- CLEANUP SCRIPT: Delete past tables
-- Warning: This deletes ALL tables scheduled in the past. 
-- Use this to clean up old test data.

DELETE FROM public.tables 
WHERE datetime < NOW();

-- Optional: If you only want to close them instead of deleting:
-- UPDATE public.tables SET status = 'completed' WHERE datetime < NOW() AND status = 'open';
