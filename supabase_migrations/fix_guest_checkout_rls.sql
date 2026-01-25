-- Fix RLS Policy for Guest Checkout
-- Allows purchase_intents to be created by Edge Functions for guest checkout

-- Drop all existing INSERT policies
DROP POLICY IF EXISTS "Users can create purchase intents" ON purchase_intents;
DROP POLICY IF EXISTS "Users and guests can create purchase intents" ON purchase_intents;
DROP POLICY IF EXISTS "Allow purchase intent creation" ON purchase_intents;

-- Recreate reserve_tickets function with proper RLS bypass
-- SECURITY DEFINER allows it to bypass RLS
CREATE OR REPLACE FUNCTION reserve_tickets(
  p_event_id UUID,
  p_user_id UUID,
  p_quantity INTEGER,
  p_guest_email TEXT DEFAULT NULL,
  p_guest_name TEXT DEFAULT NULL,
  p_guest_phone TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intent_id UUID;
  v_current_sold INTEGER;
  v_capacity INTEGER;
  v_ticket_price DECIMAL(10,2);
BEGIN
  -- Validation
  IF p_user_id IS NULL AND (p_guest_email IS NULL OR p_guest_name IS NULL) THEN
    RAISE EXCEPTION 'Must provide either user_id or guest details';
  END IF;

  -- Lock event row
  SELECT tickets_sold, capacity, ticket_price
  INTO v_current_sold, v_capacity, v_ticket_price
  FROM events
  WHERE id = p_event_id
  FOR UPDATE;

  -- Check capacity
  IF v_current_sold + p_quantity > v_capacity THEN
    RAISE EXCEPTION 'Event sold out or insufficient capacity';
  END IF;

  -- Create purchase intent (bypasses RLS due to SECURITY DEFINER)
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

  -- Increment tickets_sold
  UPDATE events
  SET tickets_sold = tickets_sold + p_quantity, updated_at = NOW()
  WHERE id = p_event_id;

  RETURN v_intent_id;
END;
$$;

-- Create minimal INSERT policy (mostly for direct inserts, not RPC)
CREATE POLICY "Allow purchase intent creation"
  ON purchase_intents FOR INSERT
  WITH CHECK (
    (auth.uid() = user_id) OR
    (user_id IS NULL AND guest_email IS NOT NULL) OR
    (auth.role() = 'service_role')
  );
