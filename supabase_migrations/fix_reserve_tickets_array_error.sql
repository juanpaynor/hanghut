-- FIX for Error 22P02: Malformed Array Literal
-- The previous version attempted "RETURNING id INTO v_reserved_ids" which fails when Postgres
-- tries to cast a single UUID result directly to an array type without braces.

CREATE OR REPLACE FUNCTION reserve_tickets(
  p_event_id UUID,
  p_user_id UUID,
  p_quantity INTEGER,
  p_guest_email TEXT DEFAULT NULL,
  p_guest_name TEXT DEFAULT NULL,
  p_guest_phone TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_intent_id UUID;
  v_ticket_price DECIMAL(10,2);
  v_reserved_ids UUID[];
BEGIN
  -- 1. Get Price (No locking needed on Event row anymore!)
  SELECT ticket_price INTO v_ticket_price FROM events WHERE id = p_event_id;

  -- 2. Create Purchase Intent (Pending)
  INSERT INTO purchase_intents (
    user_id, event_id, quantity, unit_price, subtotal,
    platform_fee, total_amount, status, expires_at,
    xendit_external_id, guest_email, guest_name, guest_phone
  ) VALUES (
    p_user_id, p_event_id, p_quantity, v_ticket_price,
    v_ticket_price * p_quantity,
    (v_ticket_price * p_quantity) * 0.10,
    (v_ticket_price * p_quantity) * 1.10,
    'pending',
    NOW() + INTERVAL '15 minutes',
    'intent_' || gen_random_uuid()::text,
    p_guest_email, p_guest_name, p_guest_phone
  ) RETURNING id INTO v_intent_id;

  -- 3. Lock and Reserve Tickets (The Core Logic)
  -- We use a 2-step CTE to safely capture the returned IDs into an array
  WITH locked_tickets AS (
    SELECT id
    FROM tickets
    WHERE event_id = p_event_id AND status = 'available'
    LIMIT p_quantity
    FOR UPDATE SKIP LOCKED -- Parallel power!
  ),
  updated_rows AS (
    UPDATE tickets
    SET 
      status = 'reserved',
      purchase_intent_id = v_intent_id,
      held_until = NOW() + INTERVAL '15 minutes',
      updated_at = NOW()
    WHERE id IN (SELECT id FROM locked_tickets)
    RETURNING id
  )
  -- Safely aggregate IDs into the array variable
  SELECT array_agg(id) INTO v_reserved_ids FROM updated_rows;

  -- 4. Validation: Did we get enough?
  -- array_length returns NULL if array is empty/null, so we check for that too
  IF v_reserved_ids IS NULL OR array_length(v_reserved_ids, 1) < p_quantity THEN
    RAISE EXCEPTION 'Not enough tickets available (Requested %, Got %)', p_quantity, COALESCE(array_length(v_reserved_ids, 1), 0);
  END IF;

  RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
