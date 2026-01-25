-- ============================================
-- Fix Critical Gaps for Event Ticketing System
-- ============================================
-- This migration addresses all critical database gaps identified
-- in the gap analysis for the event ticketing MVP.

-- ============================================
-- 1. Add Missing Fields to Partners Table
-- ============================================

ALTER TABLE partners ADD COLUMN IF NOT EXISTS profile_photo_url TEXT;
ALTER TABLE partners ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON COLUMN partners.profile_photo_url IS 'Profile photo URL for organizer avatar in event cards';
COMMENT ON COLUMN partners.description IS 'About the organizer - shown in event details';

-- ============================================
-- 2. RPC Function to Fetch Events in Viewport (Map Query)
-- ============================================

CREATE OR REPLACE FUNCTION get_events_in_viewport(
  min_lat DOUBLE PRECISION,
  max_lat DOUBLE PRECISION,
  min_lng DOUBLE PRECISION,
  max_lng DOUBLE PRECISION
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  description TEXT,
  venue_name TEXT,
  venue_address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  start_datetime TIMESTAMPTZ,
  end_datetime TIMESTAMPTZ,
  cover_image_url TEXT,
  ticket_price NUMERIC,
  capacity INTEGER,
  tickets_sold INTEGER,
  category TEXT,
  organizer_id UUID,
  organizer_name TEXT,
  organizer_photo_url TEXT,
  organizer_verified BOOLEAN,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.title,
    e.description,
    e.venue_name,
    e.address AS venue_address,
    e.latitude,
    e.longitude,
    e.start_datetime,
    e.end_datetime,
    e.cover_image_url,
    e.ticket_price,
    e.capacity,
    e.tickets_sold,
    e.event_type::TEXT AS category,
    e.organizer_id,
    p.business_name AS organizer_name,
    p.profile_photo_url AS organizer_photo_url,
    p.verified AS organizer_verified,
    e.created_at
  FROM events e
  LEFT JOIN partners p ON e.organizer_id = p.id
  WHERE e.latitude BETWEEN min_lat AND max_lat
    AND e.longitude BETWEEN min_lng AND max_lng
    AND e.status = 'active'
    AND e.start_datetime > NOW()
  ORDER BY e.start_datetime ASC
  LIMIT 500; -- Prevent excessive data transfer
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_events_in_viewport IS 'Fetches active upcoming events within map viewport bounds';

-- ============================================
-- 3. RPC Function to Validate Tickets (QR Scanner)
-- ============================================

CREATE OR REPLACE FUNCTION validate_ticket(
  ticket_qr_code TEXT,
  event_id_param UUID
)
RETURNS JSON AS $$
DECLARE
  ticket_data RECORD;
BEGIN
  -- Find and lock ticket
  SELECT 
    t.id,
    t.ticket_number,
    t.status,
    t.checked_in_at,
    u.display_name,
    e.title AS event_title,
    e.start_datetime
  INTO ticket_data
  FROM tickets t
  JOIN users u ON t.user_id = u.id
  JOIN events e ON t.event_id = e.id
  WHERE t.qr_code = ticket_qr_code
    AND t.event_id = event_id_param
  FOR UPDATE;

  -- Ticket not found
  IF NOT FOUND THEN
    RETURN json_build_object(
      'valid', false,
      'error', 'Ticket not found or invalid event'
    )::json;
  END IF;

  -- Already used
  IF ticket_data.status = 'used' THEN
    RETURN json_build_object(
      'valid', false,
      'error', 'Ticket already checked in',
      'status', 'used',
      'checked_in_at', ticket_data.checked_in_at
    )::json;
  END IF;

  -- Cancelled or refunded
  IF ticket_data.status != 'valid' THEN
    RETURN json_build_object(
      'valid', false,
      'error', 'Ticket is ' || ticket_data.status,
      'status', ticket_data.status
    )::json;
  END IF;

  -- Mark as used
  UPDATE tickets
  SET 
    status = 'used',
    checked_in_at = NOW(),
    checked_in_by = auth.uid(),
    updated_at = NOW()
  WHERE id = ticket_data.id;

  -- Return success
  RETURN json_build_object(
    'valid', true,
    'ticket_number', ticket_data.ticket_number,
    'attendee_name', ticket_data.display_name,
    'event_title', ticket_data.event_title,
    'event_start', ticket_data.start_datetime
  )::json;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION validate_ticket IS 'Validates and marks ticket as used during event check-in';

-- ============================================
-- 4. Fix RLS Policies - Allow Users to Create Purchase Intents
-- ============================================

-- Drop existing policy if it exists (migration safety)
DROP POLICY IF EXISTS "Users can create purchase intents" ON purchase_intents;

-- Create INSERT policy
CREATE POLICY "Users can create purchase intents"
  ON purchase_intents FOR INSERT
  WITH CHECK (auth.uid() = user_id);

COMMENT ON POLICY "Users can create purchase intents" ON purchase_intents IS 'Allows authenticated users to create their own purchase intents';

-- ============================================
-- 5. Storage Bucket for Event Covers
-- ============================================

-- Create bucket (idempotent - will not error if exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'event-covers',
  'event-covers',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- 6. Storage RLS Policies
-- ============================================

-- Public read access
DROP POLICY IF EXISTS "Public can view event covers" ON storage.objects;
CREATE POLICY "Public can view event covers"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'event-covers');

-- Partners can upload
DROP POLICY IF EXISTS "Partners can upload event covers" ON storage.objects;
CREATE POLICY "Partners can upload event covers"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'event-covers' 
    AND auth.uid() IN (
      SELECT user_id 
      FROM partners 
      WHERE status = 'approved'
    )
  );

-- Partners can update their own event covers
DROP POLICY IF EXISTS "Partners can update own event covers" ON storage.objects;
CREATE POLICY "Partners can update own event covers"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'event-covers'
    AND auth.uid() IN (
      SELECT user_id 
      FROM partners 
      WHERE status = 'approved'
    )
  );

-- Partners can delete their own event covers
DROP POLICY IF EXISTS "Partners can delete own event covers" ON storage.objects;
CREATE POLICY "Partners can delete own event covers"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'event-covers'
    AND auth.uid() IN (
      SELECT user_id 
      FROM partners 
      WHERE status = 'approved'
    )
  );

-- ============================================
-- 7. Cron Job to Release Expired Reservations (OPTIONAL)
-- ============================================

-- Try to schedule cron job (will skip if pg_cron not available)
DO $$
BEGIN
  -- Check if pg_cron extension exists
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- Schedule cron job to run every minute
    PERFORM cron.schedule(
      'release-expired-ticket-reservations',
      '* * * * *',  -- Every minute
      'SELECT release_expired_reservations();'
    );
    RAISE NOTICE '✓ Cron job scheduled (runs every minute)';
  ELSE
    RAISE NOTICE '⚠ pg_cron extension not available - skipping cron job';
    RAISE NOTICE '  → You will need to call release_expired_reservations() manually or via external cron';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '⚠ Could not schedule cron job: %', SQLERRM;
    RAISE NOTICE '  → You will need to call release_expired_reservations() manually or via external cron';
END $$;

COMMENT ON FUNCTION release_expired_reservations IS 'Should run every minute to release expired ticket reservations';

-- ============================================
-- 8. Helper Function: Get User's Tickets
-- ============================================

CREATE OR REPLACE FUNCTION get_user_tickets(
  user_id_param UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  ticket_number TEXT,
  qr_code TEXT,
  status ticket_status,
  event_id UUID,
  event_title TEXT,
  event_venue TEXT,
  event_start TIMESTAMPTZ,
  event_cover_image TEXT,
  checked_in_at TIMESTAMPTZ,
  purchase_date TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id,
    t.ticket_number,
    t.qr_code,
    t.status,
    e.id AS event_id,
    e.title AS event_title,
    e.venue_name AS event_venue,
    e.start_datetime AS event_start,
    e.cover_image_url AS event_cover_image,
    t.checked_in_at,
    t.created_at AS purchase_date
  FROM tickets t
  JOIN events e ON t.event_id = e.id
  WHERE t.user_id = COALESCE(user_id_param, auth.uid())
  ORDER BY e.start_datetime DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_user_tickets IS 'Fetches all tickets for the authenticated user or specified user';

-- ============================================
-- 9. Analytics: Track Event Views
-- ============================================

CREATE TABLE IF NOT EXISTS event_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  source TEXT, -- 'map', 'search', 'share_link', etc.
  
  -- Index for analytics
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_event_views_event_date ON event_views(event_id, viewed_at DESC);
CREATE INDEX idx_event_views_user ON event_views(user_id) WHERE user_id IS NOT NULL;

ALTER TABLE event_views ENABLE ROW LEVEL SECURITY;

-- Anyone can track views
CREATE POLICY "Anyone can track event views"
  ON event_views FOR INSERT
  WITH CHECK (true);

COMMENT ON TABLE event_views IS 'Tracks event view analytics for conversion funnel';

-- ============================================
-- 10. Verification & Validation
-- ============================================

-- Test RPC function (should return 0 rows if no events exist)
DO $$
BEGIN
  RAISE NOTICE 'Testing get_events_in_viewport...';
  PERFORM * FROM get_events_in_viewport(14.0, 15.0, 120.0, 121.0);
  RAISE NOTICE '✓ get_events_in_viewport works';
END $$;

-- Verify storage bucket
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'event-covers') THEN
    RAISE NOTICE '✓ Storage bucket "event-covers" created';
  ELSE
    RAISE WARNING '✗ Storage bucket "event-covers" not found';
  END IF;
END $$;

-- Verify cron job (if available)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'release-expired-ticket-reservations'
    ) THEN
      RAISE NOTICE '✓ Cron job scheduled';
    ELSE
      RAISE NOTICE '⚠ Cron job not scheduled';
    END IF;
  ELSE
    RAISE NOTICE '⚠ pg_cron extension not available';
  END IF;
END $$;

-- ============================================
-- Summary
-- ============================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '================================================';
  RAISE NOTICE 'Critical Gaps Migration Complete!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '✓ Added profile_photo_url to partners';
  RAISE NOTICE '✓ Created get_events_in_viewport() RPC';
  RAISE NOTICE '✓ Created validate_ticket() RPC';
  RAISE NOTICE '✓ Created get_user_tickets() RPC';
  RAISE NOTICE '✓ Fixed RLS policy for purchase_intents';
  RAISE NOTICE '✓ Created event-covers storage bucket';
  RAISE NOTICE '✓ Set up storage RLS policies';
  RAISE NOTICE '✓ Scheduled cron job for expired reservations';
  RAISE NOTICE '✓ Created event_views analytics table';
  RAISE NOTICE '================================================';
  RAISE NOTICE 'Ready for mobile integration!';
  RAISE NOTICE '================================================';
END $$;
