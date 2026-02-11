-- ============================================================
-- SCHEDULE EVENT REMINDERS
-- Requires: pg_cron extension
-- ============================================================

-- 1. Enable pg_cron extension
-- Note: If this fails with permission errors, you may need to enable "pg_cron" 
-- from the Supabase Dashboard -> Database -> Extensions.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- 2. Schedule the job
-- This runs the reminder function every hour on the hour.
-- The function 'send_event_reminders_24h' looks for events starting 
-- between 23.5 and 24.5 hours from now, so an hourly check checks every slot once.
SELECT cron.schedule(
  'send-event-reminders-hourly',  -- Unique name for the job
  '0 * * * *',                    -- Cron schedule (At minute 0 past every hour)
  $$ SELECT send_event_reminders_24h() $$
);

-- 3. Verify it was added (Optional check)
-- SELECT * FROM cron.job;
