-- ============================================
-- Enable Guest Checkout
-- ============================================

-- 1. Modify purchase_intents table
ALTER TABLE purchase_intents ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE purchase_intents ADD COLUMN guest_email TEXT;
ALTER TABLE purchase_intents ADD COLUMN guest_name TEXT;
ALTER TABLE purchase_intents ADD COLUMN guest_phone TEXT;

-- Constraint: Must have either user_id OR (guest_email AND guest_name)
ALTER TABLE purchase_intents ADD CONSTRAINT check_purchaser_identity 
  CHECK (user_id IS NOT NULL OR (guest_email IS NOT NULL AND guest_name IS NOT NULL));

-- 2. Modify tickets table
ALTER TABLE tickets ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE tickets ADD COLUMN guest_email TEXT;
ALTER TABLE tickets ADD COLUMN guest_name TEXT;

-- 3. Update reserve_tickets RPC
CREATE OR REPLACE FUNCTION reserve_tickets(
  p_event_id UUID,
  p_user_id UUID, -- Can now be NULL
  p_quantity INTEGER,
  p_guest_email TEXT DEFAULT NULL,
  p_guest_name TEXT DEFAULT NULL,
  p_guest_phone TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_intent_id UUID;
  v_current_sold INTEGER;
  v_capacity INTEGER;
  v_ticket_price DECIMAL(10,2);
BEGIN
  -- VALIDATION: strict check for identity
  IF p_user_id IS NULL AND (p_guest_email IS NULL OR p_guest_name IS NULL) THEN
    RAISE EXCEPTION 'Must provide either user_id or guest details';
  END IF;

  -- Lock the event row to prevent concurrent modifications
  SELECT tickets_sold, capacity, ticket_price
  INTO v_current_sold, v_capacity, v_ticket_price
  FROM events
  WHERE id = p_event_id
  FOR UPDATE; 

  -- Check capacity
  IF v_current_sold + p_quantity > v_capacity THEN
    RAISE EXCEPTION 'Event sold out or insufficient capacity';
  END IF;

  -- Create purchase intent
  INSERT INTO purchase_intents (
    user_id,
    event_id,
    quantity,
    unit_price,
    subtotal,
    platform_fee,
    total_amount,
    status,
    expires_at,
    xendit_external_id,
    guest_email,
    guest_name,
    guest_phone
  ) VALUES (
    p_user_id,
    p_event_id,
    p_quantity,
    v_ticket_price,
    v_ticket_price * p_quantity,
    (v_ticket_price * p_quantity) * 0.10, 
    (v_ticket_price * p_quantity) * 1.10,
    'pending',
    NOW() + INTERVAL '15 minutes',
    'intent_' || gen_random_uuid()::text,
    p_guest_email,
    p_guest_name,
    p_guest_phone
  ) RETURNING id INTO v_intent_id;

  -- Increment tickets_sold (reserves capacity)
  UPDATE events
  SET tickets_sold = tickets_sold + p_quantity,
      updated_at = NOW()
  WHERE id = p_event_id;

  RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql;

-- 4. Update generate_qr_code function to handle null user_id
CREATE OR REPLACE FUNCTION generate_qr_code(ticket_id UUID, event_id UUID, user_id UUID)
RETURNS TEXT AS $$
BEGIN
  -- Format: ticket_id:event_id:user_indicator:checksum
  -- If user_id is null, use 'GUEST'
  RETURN ticket_id::TEXT || ':' || event_id::TEXT || ':' || COALESCE(user_id::TEXT, 'GUEST');
END;
$$ LANGUAGE plpgsql;
