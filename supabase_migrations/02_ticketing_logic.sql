-- PART 2: Logic (Indexes, Triggers, RPCs)
-- RUN THIS AFTER PART 1.

-- 4. Create Index for fast locking
-- This uses the 'available' status created in Part 1.
CREATE INDEX IF NOT EXISTS idx_tickets_availablity ON tickets(event_id, status) 
WHERE status = 'available';

-- 5. Trigger to Pre-Mint Tickets on Event Creation (or Capacity Increase)
CREATE OR REPLACE FUNCTION mint_event_tickets()
RETURNS TRIGGER AS $$
DECLARE
  v_count INTEGER;
  i INTEGER;
BEGIN
  -- If new event or capacity increased
  IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE' AND NEW.capacity > OLD.capacity) THEN
    
    -- Calculate how many new tickets to mint
    IF TG_OP = 'INSERT' THEN
      v_count := NEW.capacity;
    ELSE
      v_count := NEW.capacity - OLD.capacity;
    END IF;

    -- Batch Insert (Loop is fine for <10k, otherwise use generate_series)
    INSERT INTO tickets (
      event_id, 
      ticket_number, 
      status, 
      tier
    )
    SELECT 
      NEW.id,
      'TK-' || UPPER(SUBSTRING(MD5(NEW.id::text || generate_series::text || RANDOM()::text) FROM 1 FOR 8)),
      'available',
      'general_admission'
    FROM generate_series(1, v_count);
    
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger
DROP TRIGGER IF EXISTS trigger_mint_tickets ON events;
CREATE TRIGGER trigger_mint_tickets
AFTER INSERT OR UPDATE OF capacity ON events
FOR EACH ROW
EXECUTE FUNCTION mint_event_tickets();

-- 6. The High-Performance Reservation Function (Replacing the old one)
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
  WITH locked_tickets AS (
    SELECT id
    FROM tickets
    WHERE event_id = p_event_id AND status = 'available'
    LIMIT p_quantity
    FOR UPDATE SKIP LOCKED -- Parallel power!
  )
  UPDATE tickets
  SET 
    status = 'reserved',
    purchase_intent_id = v_intent_id,
    held_until = NOW() + INTERVAL '15 minutes',
    updated_at = NOW()
  WHERE id IN (SELECT id FROM locked_tickets)
  RETURNING id INTO v_reserved_ids;

  -- 4. Validation: Did we get enough?
  IF array_length(v_reserved_ids, 1) < p_quantity OR v_reserved_ids IS NULL THEN
    RAISE EXCEPTION 'Not enough tickets available';
    -- Transaction rolls back, releasing locks.
  END IF;

  RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Update Inventory Janitor to handle 'reserved' tickets
CREATE OR REPLACE FUNCTION release_expired_reservations()
RETURNS INTEGER AS $$
DECLARE
  v_released_count INTEGER;
BEGIN
  -- Release Tickets held by expired intents
  WITH expired_intents AS (
    SELECT id FROM purchase_intents
    WHERE status = 'pending' AND expires_at < NOW()
  ),
  released_tickets AS (
    UPDATE tickets
    SET status = 'available',
        purchase_intent_id = NULL,
        held_until = NULL,
        user_id = NULL
    WHERE purchase_intent_id IN (SELECT id FROM expired_intents)
    RETURNING id
  )
  -- Mark intents as expired
  UPDATE purchase_intents
  SET status = 'expired', updated_at = NOW()
  WHERE id IN (SELECT id FROM expired_intents);

  GET DIAGNOSTICS v_released_count = ROW_COUNT;
  RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

-- 8. Update Issue Tickets (Finalize assignment)
CREATE OR REPLACE FUNCTION issue_tickets(p_intent_id UUID)
RETURNS JSON AS $$
DECLARE
  v_tickets JSON;
BEGIN
  -- Finalize the reserved tickets
  UPDATE tickets
  SET 
    status = 'valid',
    user_id = (SELECT user_id FROM purchase_intents WHERE id = p_intent_id),
    qr_code = generate_qr_code(id, event_id, (SELECT user_id FROM purchase_intents WHERE id = p_intent_id)),
    updated_at = NOW()
  WHERE purchase_intent_id = p_intent_id AND status = 'reserved';

  -- Return them
  SELECT json_agg(json_build_object('ticket_number', ticket_number, 'qr_code', qr_code))
  INTO v_tickets
  FROM tickets
  WHERE purchase_intent_id = p_intent_id;

  RETURN v_tickets;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
