-- BACKFILL SCRIPT
-- Run this ONCE to generate tickets for existing events.
-- Without this, old events (created before the migration) will show as "Sold Out" because they have no 'available' tickets.

DO $$
DECLARE
  v_event RECORD;
  v_tickets_to_gen INTEGER;
BEGIN
  -- Loop through all active events
  FOR v_event IN SELECT * FROM events WHERE status = 'active' OR status = 'draft' LOOP
    
    -- Calculate how many tickets are missing
    -- (Total Capacity) - (Already in Tickets Table)
    SELECT v_event.capacity - COUNT(*)
    INTO v_tickets_to_gen
    FROM tickets
    WHERE event_id = v_event.id;

    IF v_tickets_to_gen > 0 THEN
       RAISE NOTICE 'Backfilling % tickets for event: %', v_tickets_to_gen, v_event.title;
       
       INSERT INTO tickets (event_id, ticket_number, status, tier)
       SELECT 
          v_event.id,
          'TK-' || UPPER(SUBSTRING(MD5(v_event.id::text || generate_series::text || RANDOM()::text) FROM 1 FOR 8)),
          'available',
          'general_admission'
       FROM generate_series(1, v_tickets_to_gen);
    ELSE
       RAISE NOTICE 'Event already fully ticketed: %', v_event.title;
    END IF;

  END LOOP;
END;
$$;
