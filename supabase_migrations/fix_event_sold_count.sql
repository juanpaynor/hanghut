-- Fix: Create RPC to count actual sold tickets for an event
-- The tickets table has RLS (user can only see own tickets),
-- so we need SECURITY DEFINER to count ALL sold tickets.

CREATE OR REPLACE FUNCTION get_event_sold_count(p_event_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_count
  FROM tickets
  WHERE event_id = p_event_id
    AND status != 'available';

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION get_event_sold_count IS 'Returns actual sold ticket count for an event (bypasses RLS)';
