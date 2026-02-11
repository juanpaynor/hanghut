-- ============================================================
-- NOTIFICATION & GEOFENCE REFINEMENT
-- 1. Remove Chat Notifications (Too noisy)
-- 2. Add Ticket Purchase Confirmation (Critical feedback)
-- 3. Add Event Reminders (24h before)
-- 4. Fix Geofences (Only monitor JOINED events)
-- ============================================================

-- 1. REMOVE CHAT NOTIFICATIONS
-- Drop the trigger that sends push on every message
DROP TRIGGER IF EXISTS on_chat_message_sent ON messages;
DROP FUNCTION IF EXISTS notify_chat_message();


-- 2. NOTIFY BUYER ON TICKET PURCHASE
-- Create function to notify user when their purchase is confirmed
CREATE OR REPLACE FUNCTION notify_purchase_confirmation()
RETURNS TRIGGER AS $$
DECLARE
  v_event_title TEXT;
  v_buyer_id UUID;
BEGIN
  -- Only fire when status changes to completed
  IF OLD.status != 'completed' AND NEW.status = 'completed' THEN
    
    SELECT title INTO v_event_title FROM events WHERE id = NEW.event_id;
    v_buyer_id := NEW.user_id;

    -- Send Push via Edge Function
    -- Uses the existing 'send-push' function
    PERFORM net.http_post(
      url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
      ),
      body := jsonb_build_object(
        'user_id', v_buyer_id,
        'title', 'Ticket Confirmed! 🎟️',
        'body', 'You are going to ' || v_event_title || '! Tap to view tickets.',
        'data', jsonb_build_object(
          'type', 'ticket_purchase',
          'intent_id', NEW.id::TEXT,
          'event_id', NEW.event_id::TEXT
        )
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create Trigger on purchase_intents
DROP TRIGGER IF EXISTS on_purchase_confirmed ON purchase_intents;
CREATE TRIGGER on_purchase_confirmed
  AFTER UPDATE OF status ON purchase_intents
  FOR EACH ROW
  EXECUTE FUNCTION notify_purchase_confirmation();


-- 3. EVENT REMINDERS (Scheduled Function)
-- Designed to be called by pg_cron or hourly scheduler
CREATE OR REPLACE FUNCTION send_event_reminders_24h()
RETURNS void AS $$
DECLARE
  r RECORD;
BEGIN
  -- Loop through users who have events starting in ~24 hours
  FOR r IN
    -- 1. Ticket Holders
    SELECT DISTINCT t.user_id, e.title, e.id as event_id
    FROM tickets t
    JOIN events e ON e.id = t.event_id
    WHERE e.start_datetime BETWEEN NOW() + INTERVAL '23 hours 30 minutes' 
                               AND NOW() + INTERVAL '24 hours 30 minutes'
      AND t.status = 'valid'
    
    UNION
    
    -- 2. Social Table Joiners
    SELECT DISTINCT p.user_id, t.title, t.id as event_id
    FROM table_participants p
    JOIN tables t ON t.id = p.table_id
    WHERE t.datetime BETWEEN NOW() + INTERVAL '23 hours 30 minutes' 
                         AND NOW() + INTERVAL '24 hours 30 minutes'
      AND p.status = 'approved'
  LOOP
    -- Send Push
    PERFORM net.http_post(
      url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
      ),
      body := jsonb_build_object(
        'user_id', r.user_id,
        'title', 'Event Tomorrow! ⏰',
        'body', 'Reminder: ' || r.title || ' is starting regularly in 24 hours.',
        'data', jsonb_build_object(
          'type', 'event_reminder',
          'event_id', r.event_id::TEXT
        )
      )
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. SMART GEOFENCING (Joined Events Only)
-- Updates the cache-fetch RPC to only return events the user is participating in.
-- This effectively prevents "Entered Zone" alerts for random events.
CREATE OR REPLACE FUNCTION get_nearby_tables(
  lat double precision,
  lng double precision,
  radius_meters double precision
)
RETURNS table (
  id uuid,
  title text,
  latitude double precision,
  longitude double precision,
  distance_meters double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.title,
    t.latitude,
    t.longitude,
    st_distance(
      t.location,
      st_point(lng, lat)::geography
    ) as distance_meters
  FROM
    tables t
  WHERE
    t.status = 'open'
    -- Spatial Filter
    AND st_dwithin(
      t.location,
      st_point(lng, lat)::geography,
      radius_meters
    )
    -- Participation Filter (The Fix)
    AND (
      -- Is a Social Participant?
      EXISTS (
        SELECT 1 FROM table_participants tp 
        WHERE tp.table_id = t.id 
          AND tp.user_id = auth.uid() 
          AND tp.status = 'approved'
      )
      OR
      -- Is a Ticket Holder?
      -- Assumes event_id maps to tables.id in the unified schema
      EXISTS (
        SELECT 1 FROM tickets tk 
        WHERE tk.event_id = t.id 
          AND tk.user_id = auth.uid() 
          AND tk.status = 'valid'
      )
    )
  LIMIT 100;
END;
$$;
