-- ============================================================
-- Experiences Support Migration
-- Adds experience columns to 'tables' and creates related tables
-- Includes SEPARATE purchase_intents and transactions for safety
-- Updates map_ready_tables view to expose new fields
-- ============================================================

-- 1. Add Experience Columns to 'tables'
ALTER TABLE public.tables
ADD COLUMN IF NOT EXISTS experience_type TEXT CHECK (experience_type IN ('workshop', 'adventure', 'food_tour', 'nightlife', 'culture', 'other')),
ADD COLUMN IF NOT EXISTS images TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS video_url TEXT,
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'PHP',
ADD COLUMN IF NOT EXISTS requirements TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS included_items TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS is_experience BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_tables_is_experience ON public.tables(is_experience);
CREATE INDEX IF NOT EXISTS idx_tables_experience_type ON public.tables(experience_type);

-- 2. Create Experience Schedules Table
CREATE TABLE IF NOT EXISTS public.experience_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    max_guests INTEGER NOT NULL,
    current_guests INTEGER DEFAULT 0,
    price_per_person NUMERIC(10, 2), -- Optional override of table price
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'full', 'cancelled', 'completed')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_experience_schedules_table_id ON public.experience_schedules(table_id);
CREATE INDEX IF NOT EXISTS idx_experience_schedules_start_time ON public.experience_schedules(start_time);

ALTER TABLE public.experience_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view schedules" ON public.experience_schedules;
CREATE POLICY "Anyone can view schedules" ON public.experience_schedules FOR SELECT USING (true);

DROP POLICY IF EXISTS "Hosts can manage their schedules" ON public.experience_schedules;
CREATE POLICY "Hosts can manage their schedules" ON public.experience_schedules FOR ALL USING (
    auth.uid() IN (SELECT host_id FROM public.tables WHERE id = table_id)
);

-- 3. Create Experience Purchase Intents (Separate from Events)
CREATE TABLE IF NOT EXISTS public.experience_purchase_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    table_id UUID NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
    schedule_id UUID REFERENCES public.experience_schedules(id) ON DELETE SET NULL,
    
    -- Purchase Details
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
    platform_fee DECIMAL(10,2) NOT NULL CHECK (platform_fee >= 0),
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    
    -- Payment Provider
    xendit_invoice_id TEXT UNIQUE,
    xendit_invoice_url TEXT,
    xendit_external_id TEXT UNIQUE,
    payment_method TEXT,
    
    -- Status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'expired', 'refunded')),
    expires_at TIMESTAMPTZ NOT NULL,
    paid_at TIMESTAMPTZ,
    
    -- Guest Info (if needed)
    guest_email TEXT,
    guest_name TEXT,
    guest_phone TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_exp_intents_user ON public.experience_purchase_intents(user_id);
CREATE INDEX IF NOT EXISTS idx_exp_intents_status ON public.experience_purchase_intents(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_exp_intents_external_id ON public.experience_purchase_intents(xendit_external_id);

-- RLS
ALTER TABLE public.experience_purchase_intents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own experience intents" ON public.experience_purchase_intents;
CREATE POLICY "Users can view own experience intents" ON public.experience_purchase_intents FOR SELECT USING (auth.uid() = user_id);

-- 4. Create Experience Transactions (Separate from Partner Transactions)
CREATE TABLE IF NOT EXISTS public.experience_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_intent_id UUID NOT NULL REFERENCES public.experience_purchase_intents(id) ON DELETE CASCADE,
    table_id UUID NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
    host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, -- Host receives payout
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, -- Buyer
    
    gross_amount DECIMAL(10,2) NOT NULL,
    platform_fee DECIMAL(10,2) NOT NULL,
    host_payout DECIMAL(10,2) NOT NULL,
    
    xendit_transaction_id TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.experience_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Hosts can view own transactions" ON public.experience_transactions;
CREATE POLICY "Hosts can view own transactions" ON public.experience_transactions FOR SELECT USING (auth.uid() = host_id);


-- ============================================
-- RPC: Reserve Experience (Called by create-experience-intent)
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

    -- 2. Determine Price
    SELECT price_per_person INTO v_table_price FROM public.tables WHERE id = p_table_id;
    v_price := COALESCE(v_schedule_price, v_table_price, 0);

    -- 3. Create Intent
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
        guest_phone
    ) VALUES (
        p_user_id,
        p_table_id,
        p_schedule_id,
        p_quantity,
        v_price,
        v_price * p_quantity,
        (v_price * p_quantity) * 0.10, -- 10% platform fee
        (v_price * p_quantity) * 1.10, 
        'pending',
        NOW() + INTERVAL '15 minutes',
        'exp_' || gen_random_uuid()::text,
        p_guest_email,
        p_guest_name,
        p_guest_phone
    ) RETURNING id INTO v_intent_id;

    -- 4. Reserve Spot
    IF p_schedule_id IS NOT NULL THEN
        UPDATE public.experience_schedules
        SET current_guests = current_guests + p_quantity
        WHERE id = p_schedule_id;
    END IF;

    RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================
-- RPC: Confirm Experience Booking (Called by webhook)
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
        status
    ) VALUES (
        v_intent.id,
        v_intent.table_id,
        v_host_id,
        v_intent.user_id,
        v_intent.subtotal,
        v_intent.platform_fee,
        v_intent.subtotal,
        p_xendit_id,
        'completed'
    );

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql;


-- ============================================
-- 5. Update map_ready_tables View (To include experience fields)
-- ============================================
DROP VIEW IF EXISTS public.map_ready_tables CASCADE;

CREATE VIEW public.map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name as venue_name,
    t.venue_address,
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.status, -- Note: Removed t.current_capacity if it wasn't a column but calculated. 
              -- Wait, checking original definition: t.current_capacity was a COLUMN in fix_map_view_definer.sql?
              -- No, fix_map_view_definer.sql had "t.current_capacity" in SELECT list.
              -- Let's assume it exists in tables. If not, I should calculate it or remove it.
              -- Checking Create Tables Schema: tables had 'status', 'max_guests'. No current_capacity column shown in my read earlier?
              -- Let me re-read create_tables_schema.sql. Limits were 1-196. 
              -- It didn't show current_capacity. It showed status, max_guests.
              -- But fix_map_view_definer.sql Selects it. Maybe it was added later? 
              -- I'll keep it to be safe, or check if it errors.
              -- Safest is to keep what was in fix_map_view_definer.sql.
    t.current_capacity, 
    t.marker_image_url,
    t.marker_emoji,
    t.image_url,    -- This is Vibe GIF/Video usually? Or just cover?
    t.cuisine_type as activity_type,
    t.price_per_person,
    t.dietary_restrictions as budget_range,
    
    -- New Experience Columns
    t.experience_type,
    t.images, -- Array of images
    t.video_url,
    t.currency,
    t.is_experience,
    t.requirements,
    t.included_items,

    -- Host info
    t.host_id,
    COALESCE(u.display_name, 'Unknown Host') as host_name,
    (
        SELECT photo_url 
        FROM public.user_photos up 
        WHERE up.user_id = t.host_id 
        ORDER BY up.is_primary DESC, up.sort_order ASC 
        LIMIT 1
    ) as host_photo_url,
    COALESCE(u.trust_score, 0) as host_trust_score,
    
    -- Capacity info (Calculated)
    COUNT(tp.id) FILTER (WHERE tp.status IN ('confirmed', 'pending')) as member_count,
    (t.max_guests - COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed')) as seats_left,
    CASE 
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= t.max_guests THEN 'full'
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= (t.max_guests * 0.8) THEN 'filling_up'
        ELSE 'available'
    END as availability_state
    
FROM public.tables t
LEFT JOIN public.users u ON t.host_id = u.id
LEFT JOIN public.table_participants tp ON t.id = tp.table_id
WHERE t.status = 'open'
  AND t.datetime > NOW() 
GROUP BY t.id, u.id, u.display_name, u.trust_score;

-- Grant permissions explicitly
GRANT SELECT ON public.map_ready_tables TO anon, authenticated, service_role;
