-- ============================================================
-- RECOVERY MIGRATION: Restore Missing Partners & Events Tables
-- ============================================================
-- The error "relation public.partners does not exist" suggests
-- the base ticketing schema was never applied. This script
-- restores the core tables idempotently.

-- 1. Create Types if not exist
DO $$ BEGIN
    CREATE TYPE partner_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE partner_pricing_model AS ENUM ('standard', 'custom', 'tiered');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE event_status AS ENUM ('draft', 'active', 'sold_out', 'cancelled', 'completed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE event_type AS ENUM ('concert', 'workshop', 'conference', 'sports', 'social', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE purchase_intent_status AS ENUM ('pending', 'completed', 'failed', 'expired', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_status AS ENUM ('valid', 'used', 'cancelled', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payout_status AS ENUM ('pending_request', 'approved', 'processing', 'completed', 'failed', 'rejected');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Create Partners Table
CREATE TABLE IF NOT EXISTS public.partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Business Information
  business_name TEXT NOT NULL,
  business_type TEXT, 
  registration_number TEXT, 
  tax_id TEXT, 
  
  -- Bank Details
  bank_name TEXT,
  bank_account_number TEXT,
  bank_account_name TEXT,
  
  -- Pricing Configuration
  pricing_model partner_pricing_model DEFAULT 'standard',
  custom_percentage DECIMAL(5,2), 
  custom_per_ticket DECIMAL(10,2), 
  promotional_until TIMESTAMPTZ, 
  volume_tier_enabled BOOLEAN DEFAULT false,
  pass_fees_to_customer BOOLEAN DEFAULT TRUE, -- Added directly here
  
  -- Status & Metadata
  status partner_status DEFAULT 'pending',
  verified BOOLEAN DEFAULT false,
  admin_notes TEXT,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ
);

-- 3. Create Events Table
CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  event_type event_type DEFAULT 'other',
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  venue_name TEXT,
  start_datetime TIMESTAMPTZ NOT NULL,
  end_datetime TIMESTAMPTZ,
  capacity INTEGER NOT NULL CHECK (capacity > 0),
  tickets_sold INTEGER DEFAULT 0 CHECK (tickets_sold >= 0),
  ticket_price DECIMAL(10,2) NOT NULL CHECK (ticket_price >= 0),
  min_tickets_per_purchase INTEGER DEFAULT 1,
  max_tickets_per_purchase INTEGER DEFAULT 10,
  cover_image_url TEXT,
  images JSONB,
  status event_status DEFAULT 'draft',
  is_featured BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ
);

-- 4. Create Purchase Intents Table (General Events)
-- Note: Experiences uses a separate table 'experience_purchase_intents'.
CREATE TABLE IF NOT EXISTS public.purchase_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
  platform_fee DECIMAL(10,2) NOT NULL CHECK (platform_fee >= 0),
  payment_processing_fee DECIMAL(10,2) DEFAULT 0 CHECK (payment_processing_fee >= 0),
  total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
  fee_percentage DECIMAL(5,2),
  pricing_note TEXT,
  xendit_invoice_id TEXT UNIQUE,
  xendit_invoice_url TEXT,
  xendit_external_id TEXT UNIQUE,
  payment_method TEXT,
  status purchase_intent_status DEFAULT 'pending',
  expires_at TIMESTAMPTZ NOT NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Enable RLS
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own partner profile" ON public.partners;
CREATE POLICY "Users can view own partner profile" ON public.partners FOR SELECT USING (auth.uid() = user_id);

-- 6. Add partner_id to tables (from add_host_partner_link.sql)
ALTER TABLE public.tables 
ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id);
CREATE INDEX IF NOT EXISTS idx_tables_partner_id ON public.tables(partner_id);

ALTER TABLE public.experience_transactions
ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id);
CREATE INDEX IF NOT EXISTS idx_experience_transactions_partner_id ON public.experience_transactions(partner_id);

-- 7. Grant Permissions
GRANT ALL ON public.partners TO postgres, service_role;
GRANT SELECT ON public.partners TO authenticated, anon;
