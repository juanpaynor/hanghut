-- ============================================================================
-- CRON JOB: Clean up expired stories (older than 24 hours)
-- ============================================================================
-- Stories are ephemeral — they disappear from the UI after 24h.
-- This cron runs weekly (Sunday 3 AM UTC) to delete stale rows 
-- and keep the database clean without impacting performance.
--
-- HOW TO ENABLE:
-- 1. Go to Supabase Dashboard → Database → Extensions
-- 2. Enable the `pg_cron` extension (if not already enabled)
-- 3. Run this SQL in the SQL Editor
-- ============================================================================

-- Enable pg_cron if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule: every Sunday at 3:00 AM UTC
SELECT cron.schedule(
  'cleanup-expired-stories',
  '0 3 * * 0',  -- minute=0, hour=3, day=*, month=*, weekday=0(Sunday)
  $$
    DELETE FROM posts
    WHERE is_story = true
      AND created_at < NOW() - INTERVAL '24 hours';
  $$
);

-- To verify the job was created:
-- SELECT * FROM cron.job;

-- To remove the job later if needed:
-- SELECT cron.unschedule('cleanup-expired-stories');
