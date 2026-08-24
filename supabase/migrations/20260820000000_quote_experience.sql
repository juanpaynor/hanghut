-- quote_experience: returns the EXACT price breakdown reserve_experience will
-- charge, without reserving. Used by the app's experience checkout so the
-- displayed total matches the Xendit charge (previously the screen showed only
-- the subtotal and omitted the service fee).
--
-- SECURITY DEFINER so a buyer can read the partner's fee settings (custom_percentage,
-- pass_fees_to_customer) without needing direct RLS read access to `partners`.
-- Fee logic is kept byte-for-byte in sync with reserve_experience.

CREATE OR REPLACE FUNCTION public.quote_experience(
  p_table_id uuid,
  p_schedule_id uuid,
  p_quantity integer
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_table_price      DECIMAL(10,2);
  v_schedule_price   DECIMAL(10,2);
  v_price            DECIMAL(10,2);
  v_partner_id       UUID;
  v_custom_percentage DECIMAL(5,2);
  v_pass_fees        BOOLEAN;
  v_applied_percentage DECIMAL(5,2);
  v_subtotal         DECIMAL(10,2);
  v_fee_amount       DECIMAL(10,2);
  v_platform_fee     DECIMAL(10,2);
  v_total_amount     DECIMAL(10,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity < 1 THEN
    p_quantity := 1;
  END IF;

  -- Price: schedule overrides table, mirroring reserve_experience.
  IF p_schedule_id IS NOT NULL THEN
    SELECT price_per_person INTO v_schedule_price
    FROM public.experience_schedules WHERE id = p_schedule_id;
  END IF;

  SELECT price_per_person, partner_id
  INTO v_table_price, v_partner_id
  FROM public.tables WHERE id = p_table_id;

  v_price := COALESCE(v_schedule_price, v_table_price, 0);

  -- Partner fee settings (defaults match reserve_experience: 15%, passed to customer).
  SELECT COALESCE(custom_percentage, 15.00),
         COALESCE(pass_fees_to_customer, TRUE)
  INTO v_custom_percentage, v_pass_fees
  FROM public.partners WHERE id = v_partner_id;

  v_applied_percentage := COALESCE(v_custom_percentage, 15.00);
  v_subtotal := v_price * p_quantity;
  v_fee_amount := v_subtotal * (v_applied_percentage / 100.0);

  IF COALESCE(v_pass_fees, TRUE) THEN
    v_platform_fee := v_fee_amount;
    v_total_amount := v_subtotal + v_fee_amount;
  ELSE
    v_platform_fee := 0;
    v_total_amount := v_subtotal;
  END IF;

  RETURN jsonb_build_object(
    'unit_price', v_price,
    'quantity', p_quantity,
    'subtotal', v_subtotal,
    'fee_percentage', v_applied_percentage,
    'fees_passed_to_customer', COALESCE(v_pass_fees, TRUE),
    'platform_fee', v_platform_fee,
    'total_amount', v_total_amount
  );
END;
$$;

-- SECURITY DEFINER functions default to PUBLIC execute; lock down then grant.
REVOKE EXECUTE ON FUNCTION public.quote_experience(uuid, uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_experience(uuid, uuid, integer) TO authenticated;
