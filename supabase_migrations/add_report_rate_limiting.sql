-- ========================================
-- REPORT RATE LIMITING
-- Prevents abuse by limiting how many reports a user can submit
-- ========================================

-- Function to enforce rate limits on report submissions
CREATE OR REPLACE FUNCTION enforce_report_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    reports_last_hour INTEGER;
    reports_last_day INTEGER;
BEGIN
    -- Count reports in the last hour
    SELECT COUNT(*) INTO reports_last_hour
    FROM public.reports
    WHERE reporter_id = NEW.reporter_id
    AND created_at > NOW() - INTERVAL '1 hour';

    -- Count reports in the last 24 hours
    SELECT COUNT(*) INTO reports_last_day
    FROM public.reports
    WHERE reporter_id = NEW.reporter_id
    AND created_at > NOW() - INTERVAL '24 hours';

    -- Enforce hourly limit (10 reports)
    IF reports_last_hour >= 10 THEN
        RAISE EXCEPTION 'Rate limit exceeded. You can only submit 10 reports per hour. Please try again later.'
            USING HINT = 'Wait at least 1 hour before submitting more reports';
    END IF;

    -- Enforce daily limit (50 reports)
    IF reports_last_day >= 50 THEN
        RAISE EXCEPTION 'Daily report limit exceeded. You can only submit 50 reports per day.'
            USING HINT = 'Your report limit will reset in 24 hours';
    END IF;

    -- Allow the insert if limits are not exceeded
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to check rate limits before insert
DROP TRIGGER IF EXISTS check_report_rate_limit ON public.reports;
CREATE TRIGGER check_report_rate_limit
    BEFORE INSERT ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION enforce_report_rate_limit();

-- Add index to optimize rate limit checks
CREATE INDEX IF NOT EXISTS idx_reports_reporter_created 
ON public.reports(reporter_id, created_at DESC);

COMMENT ON FUNCTION enforce_report_rate_limit() IS 'Prevents report spam by limiting submissions to 10/hour and 50/day per user';
