-- Fix get_user_tickets to include price_paid from purchase_intents
DROP FUNCTION IF EXISTS get_user_tickets(UUID);

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
  event_end TIMESTAMPTZ,
  event_cover_image TEXT,
  checked_in_at TIMESTAMPTZ,
  purchase_date TIMESTAMPTZ,
  price_paid NUMERIC
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
    e.end_datetime AS event_end,
    e.cover_image_url AS event_cover_image,
    t.checked_in_at,
    t.created_at AS purchase_date,
    COALESCE(pi.unit_price, e.ticket_price) AS price_paid  -- Use purchase intent unit price, fallback to event ticket price
  FROM tickets t
  JOIN events e ON t.event_id = e.id
  LEFT JOIN purchase_intents pi ON t.purchase_intent_id = pi.id
  WHERE t.user_id = COALESCE(user_id_param, auth.uid())
  ORDER BY e.start_datetime DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_user_tickets IS 'Fetches all tickets for the authenticated user with price paid from purchase intent';
