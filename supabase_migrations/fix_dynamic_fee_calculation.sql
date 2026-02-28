-- ============================================================
-- Dynamic Fee Calculation Logic Update
-- 1. Adds 'pass_fees_to_customer' to partners
-- 2. Adds fee tracking columns to experience_purchase_intents
-- 3. Updates reserve_experience to calculate fees dynamically
-- 4. Updates confirm_experience_booking to handle payouts correctly
-- ============================================================

-- 1. Add 'pass_fees_to_customer' column to partners if not exists
ALTER TABLE public.partners 
ADD COLUMN IF NOT EXISTS pass_fees_to_customer BOOLEAN DEFAULT TRUE;

-- Enforce Default to TRUE (since schema dump showed FALSE)
ALTER TABLE public.partners 
ALTER COLUMN pass_fees_to_customer SET DEFAULT TRUE;

COMMENT ON COLUMN public.partners.pass_fees_to_customer IS 'If true, fee is added on top (Customer pays). If false, fee is deducted from payout (Host pays).';

-- 2. Add Fee Tracking to experience_purchase_intents (to persist logic snapshot)
ALTER TABLE public.experience_purchase_intents
ADD COLUMN IF NOT EXISTS fee_percentage DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS fees_passed_to_customer BOOLEAN;

-- ============================================
-- UPDATE RPC: reserve_experience
-- ============================================
CREATE OR REPLACE FUNCTION public.reserve_experience(
    p_table_id UUID,
    p_schedule_id UUID,
    p_user_id UUID,
    p_quantity INTEGER,
    p_guest_email TEXT DEFAULT NULL,
    p_guest_name TEXT DEFAULT NULL,
    p_guest_phone TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_intent_id UUID;
    v_current_guests INTEGER;
    v_max_guests INTEGER;
    v_price DECIMAL(10,2);
    v_table_price DECIMAL(10,2);
    v_schedule_price DECIMAL(10,2);
    
    -- Partner Fee Settings
    v_partner_id UUID;
    v_custom_percentage DECIMAL(5,2);
    v_pass_fees BOOLEAN;
    
    -- Calculation Variables
    v_applied_percentage DECIMAL(5,2);
    v_fee_amount DECIMAL(10,2);
    v_subtotal DECIMAL(10,2);
    v_platform_fee_charged DECIMAL(10,2); -- What the user pays in Xendit
    v_total_amount DECIMAL(10,2);
BEGIN
    -- 1. Check Capacity (Lock row)
    IF p_schedule_id IS NOT NULL THEN
        SELECT current_guests, max_guests, price_per_person
        INTO v_current_guests, v_max_guests, v_schedule_price
        FROM public.experience_schedules
        WHERE id = p_schedule_id
        FOR UPDATE;
        
        IF v_current_guests + p_quantity > v_max_guests THEN
            RAISE EXCEPTION 'Schedule is full';
        END IF;
    END IF;

    -- 1.5. Validate User ID (No Guest Checkout)
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID is required. Guest checkout is not allowed.';
    END IF;

    -- 2. Get Table Price and Partner ID
    SELECT price_per_person, partner_id 
    INTO v_table_price, v_partner_id
    FROM public.tables WHERE id = p_table_id;
    
    v_price := COALESCE(v_schedule_price, v_table_price, 0);

    -- 3. Get Partner Fee Logic
    SELECT 
        COALESCE(custom_percentage, 15.00), -- Default to 15% if null
        COALESCE(pass_fees_to_customer, TRUE) -- Default to True (Customer pays)
    INTO v_custom_percentage, v_pass_fees
    FROM public.partners
    WHERE id = v_partner_id;
    
    -- 4. Calculate Fees
    v_applied_percentage := COALESCE(v_custom_percentage, 15.00);
    v_subtotal := v_price * p_quantity;
    
    -- Calculate the fee value based on subtotal
    v_fee_amount := v_subtotal * (v_applied_percentage / 100.0);
    
    IF v_pass_fees THEN
        -- Case A: Customer Pays (Add-on)
        v_platform_fee_charged := v_fee_amount;
        v_total_amount := v_subtotal + v_fee_amount;
    ELSE
        -- Case B: Host Pays (Absorbed)
        v_platform_fee_charged := 0; -- User sees 0 fee
        v_total_amount := v_subtotal; -- User pays just the price
    END IF;

    -- 5. Create Intent
    INSERT INTO public.experience_purchase_intents (
        user_id,
        table_id,
        schedule_id,
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
        guest_phone,
        
        -- Persist logic
        fee_percentage,
        fees_passed_to_customer
    ) VALUES (
        p_user_id,
        p_table_id,
        p_schedule_id,
        p_quantity,
        v_price,
        v_subtotal,
        v_platform_fee_charged, -- This goes to Xendit invoice
        v_total_amount,
        'pending',
        NOW() + INTERVAL '15 minutes',
        'exp_' || gen_random_uuid()::text,
        p_guest_email,
        p_guest_name,
        p_guest_phone,
        
        v_applied_percentage,
        v_pass_fees
    ) RETURNING id INTO v_intent_id;

    -- 6. Reserve Spot
    IF p_schedule_id IS NOT NULL THEN
        UPDATE public.experience_schedules
        SET current_guests = current_guests + p_quantity
        WHERE id = p_schedule_id;
    END IF;

    RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================
-- UPDATE RPC: confirm_experience_booking
-- ============================================
CREATE OR REPLACE FUNCTION public.confirm_experience_booking(
    p_intent_id UUID,
    p_payment_method TEXT,
    p_xendit_id TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_intent RECORD;
    v_host_id UUID;
    
    v_real_platform_revenue DECIMAL(10,2);
    v_host_payout DECIMAL(10,2);
BEGIN
    -- Fetch Intent
    SELECT * INTO v_intent FROM public.experience_purchase_intents WHERE id = p_intent_id;
    
    IF v_intent IS NULL OR v_intent.status = 'completed' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Intent not found or already completed');
    END IF;

    -- Update Intent
    UPDATE public.experience_purchase_intents
    SET status = 'completed',
        paid_at = NOW(),
        payment_method = p_payment_method
    WHERE id = p_intent_id;

    -- Add to Table Participants
    INSERT INTO public.table_participants (
        table_id,
        user_id,
        status
    ) VALUES (
        v_intent.table_id,
        v_intent.user_id,
        'confirmed'
    ) ON CONFLICT (table_id, user_id) DO NOTHING; 

    -- Fetch Host ID
    SELECT host_id INTO v_host_id FROM public.tables WHERE id = v_intent.table_id;

    -- Calculate Payout & Revenue based on stored logic
    -- Logic: 
    -- If passed to customer, Revenue = collected platform_fee. Payout = Subtotal.
    -- If absorbed by host, Revenue = Subtotal * %. Payout = Subtotal - Revenue.
    
    IF v_intent.fees_passed_to_customer THEN
        v_real_platform_revenue := v_intent.platform_fee; -- We collected it on top
        v_host_payout := v_intent.subtotal; -- Host gets full ticket price
    ELSE
        -- Host pays: Fee is inside the subtotal
        -- Recalculate fee amount using stored percentage
        v_real_platform_revenue := v_intent.subtotal * (COALESCE(v_intent.fee_percentage, 15.00) / 100.0);
        v_host_payout := v_intent.subtotal - v_real_platform_revenue;
    END IF;

    -- Create Transaction
    INSERT INTO public.experience_transactions (
        purchase_intent_id,
        table_id,
        host_id,
        user_id,
        gross_amount,
        platform_fee,
        host_payout,
        xendit_transaction_id,
        status,
        partner_id -- Ensure partner_id is filled (it was added in add_host_partner_link.sql)
    ) VALUES (
        v_intent.id,
        v_intent.table_id,
        v_host_id,
        v_intent.user_id,
        v_intent.subtotal,       -- Gross sales (ticket sales only, excluding customer-paid fees? Or Total?)
                                 -- Standard accounting: Gross Volume = What customer paid. 
                                 -- But 'gross_amount' usually means the Ticket Value.
                                 -- Let's stick to Ticket Sales Volume for 'gross_amount' for consistency with host expectations.
        v_real_platform_revenue, -- Our actual revenue
        v_host_payout,           -- What we send to host
        p_xendit_id,
        'completed',
        (SELECT partner_id FROM public.tables WHERE id = v_intent.table_id)
    );

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
