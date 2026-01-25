-- Function to issue tickets for a completed purchase intent
CREATE OR REPLACE FUNCTION issue_tickets(p_intent_id UUID)
RETURNS JSON AS $$
DECLARE
  v_intent RECORD;
  v_tickets JSON;
  i INTEGER;
  v_new_ticket_id UUID;
  v_ticket_number TEXT;
  v_qr_code TEXT;
BEGIN
  -- Get intent details
  SELECT * INTO v_intent FROM purchase_intents WHERE id = p_intent_id;
  
  IF v_intent IS NULL THEN
    RAISE EXCEPTION 'Purchase intent not found';
  END IF;

  -- Check if tickets already exist (idempotency)
  SELECT json_agg(json_build_object('ticket_number', ticket_number, 'qr_code', qr_code))
  INTO v_tickets
  FROM tickets
  WHERE purchase_intent_id = p_intent_id;

  IF v_tickets IS NOT NULL THEN
    RETURN v_tickets;
  END IF;

  -- Loop to create tickets
  FOR i IN 1..v_intent.quantity LOOP
    v_new_ticket_id := uuid_generate_v4();
    v_ticket_number := generate_ticket_number();
    
    -- Generate QR code data using helper
    -- Note: generate_qr_code handles NULL user_id for guests
    v_qr_code := generate_qr_code(v_new_ticket_id, v_intent.event_id, v_intent.user_id);

    INSERT INTO tickets (
      id,
      purchase_intent_id,
      event_id,
      user_id,
      ticket_number,
      qr_code,
      status,
      guest_email,
      guest_name,
      created_at,
      updated_at
    ) VALUES (
      v_new_ticket_id,
      v_intent.id,
      v_intent.event_id,
      v_intent.user_id,
      v_ticket_number,
      v_qr_code,
      'valid',
      v_intent.guest_email,
      v_intent.guest_name,
      NOW(),
      NOW()
    );
  END LOOP;

  -- Return the created tickets
  SELECT json_agg(json_build_object('ticket_number', ticket_number, 'qr_code', qr_code))
  INTO v_tickets
  FROM tickets
  WHERE purchase_intent_id = p_intent_id;

  RETURN v_tickets;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
