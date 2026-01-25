-- ============================================
-- HangHut Event Ticketing System - Database Schema
-- ============================================
-- This migration creates the complete database schema for 
-- the event ticketing and partner management system.

-- ============================================
-- ENUMS (Status Types)
-- ============================================

CREATE TYPE partner_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
CREATE TYPE partner_pricing_model AS ENUM ('standard', 'custom', 'tiered');
CREATE TYPE event_status AS ENUM ('draft', 'active', 'sold_out', 'cancelled', 'completed');
CREATE TYPE event_type AS ENUM ('concert', 'workshop', 'conference', 'sports', 'social', 'other');
CREATE TYPE purchase_intent_status AS ENUM ('pending', 'completed', 'failed', 'expired', 'cancelled');
CREATE TYPE ticket_status AS ENUM ('valid', 'used', 'cancelled', 'refunded');
CREATE TYPE transaction_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE payout_status AS ENUM ('pending_request', 'approved', 'processing', 'completed', 'failed', 'rejected');

-- ============================================
-- TABLE: partners
-- Event organizers who create and manage events
-- ============================================

CREATE TABLE partners (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Business Information
  business_name TEXT NOT NULL,
  business_type TEXT, -- 'individual', 'company', 'venue'
  registration_number TEXT, -- DTI/SEC
  tax_id TEXT, -- TIN
  
  -- Bank Details (for payouts)
  bank_name TEXT,
  bank_account_number TEXT,
  bank_account_name TEXT,
  
  -- Pricing Configuration
  pricing_model partner_pricing_model DEFAULT 'standard',
  custom_percentage DECIMAL(5,2), -- e.g., 7.50 for 7.5%
  custom_per_ticket DECIMAL(10,2), -- e.g., 15.00 for ₱15 per ticket
  promotional_until TIMESTAMPTZ, -- time-limited promo rate
  volume_tier_enabled BOOLEAN DEFAULT false,
  
  -- Status & Metadata
  status partner_status DEFAULT 'pending',
  verified BOOLEAN DEFAULT false,
  admin_notes TEXT,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT valid_custom_percentage CHECK (custom_percentage IS NULL OR (custom_percentage >= 0 AND custom_percentage <= 100)),
  CONSTRAINT valid_custom_per_ticket CHECK (custom_per_ticket IS NULL OR custom_per_ticket >= 0)
);

-- ============================================
-- TABLE: events
-- Ticketed events created by partners
-- ============================================

CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organizer_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  
  -- Event Details
  title TEXT NOT NULL,
  description TEXT,
  event_type event_type DEFAULT 'other',
  
  -- Location
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  venue_name TEXT,
  
  -- Timing
  start_datetime TIMESTAMPTZ NOT NULL,
  end_datetime TIMESTAMPTZ,
  
  -- Ticketing
  capacity INTEGER NOT NULL CHECK (capacity > 0),
  tickets_sold INTEGER DEFAULT 0 CHECK (tickets_sold >= 0),
  ticket_price DECIMAL(10,2) NOT NULL CHECK (ticket_price >= 0),
  min_tickets_per_purchase INTEGER DEFAULT 1,
  max_tickets_per_purchase INTEGER DEFAULT 10,
  
  -- Media
  cover_image_url TEXT,
  images JSONB, -- array of image URLs
  
  -- Status
  status event_status DEFAULT 'draft',
  is_featured BOOLEAN DEFAULT false,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT tickets_sold_within_capacity CHECK (tickets_sold <= capacity),
  CONSTRAINT valid_datetime_range CHECK (end_datetime IS NULL OR end_datetime > start_datetime),
  CONSTRAINT valid_ticket_purchase_limits CHECK (max_tickets_per_purchase >= min_tickets_per_purchase)
);

-- ============================================
-- TABLE: purchase_intents
-- Tracks the purchase flow from intent to completion
-- ============================================

CREATE TABLE purchase_intents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Parties
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  
  -- Purchase Details
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
  platform_fee DECIMAL(10,2) NOT NULL CHECK (platform_fee >= 0),
  payment_processing_fee DECIMAL(10,2) DEFAULT 0 CHECK (payment_processing_fee >= 0),
  total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
  
  -- Pricing Rule Applied
  fee_percentage DECIMAL(5,2), -- what % was charged (for audit)
  pricing_note TEXT, -- e.g., "Custom rate - High volume partner"
  
  -- Payment Provider (Xendit)
  xendit_invoice_id TEXT UNIQUE,
  xendit_invoice_url TEXT,
  xendit_external_id TEXT UNIQUE, -- our reference
  payment_method TEXT, -- gcash, card, maya, etc.
  
  -- Status & Timing
  status purchase_intent_status DEFAULT 'pending',
  expires_at TIMESTAMPTZ NOT NULL, -- 10-15 min from creation
  paid_at TIMESTAMPTZ,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLE: tickets
-- Individual tickets issued after successful payment
-- ============================================

CREATE TABLE tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Relationships
  purchase_intent_id UUID NOT NULL REFERENCES purchase_intents(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Ticket Details
  ticket_number TEXT UNIQUE NOT NULL, -- human-readable reference
  qr_code TEXT UNIQUE NOT NULL, -- QR code data
  
  -- Check-in
  status ticket_status DEFAULT 'valid',
  checked_in_at TIMESTAMPTZ,
  checked_in_by UUID REFERENCES users(id), -- staff who scanned
  
  -- Metadata
  tier TEXT DEFAULT 'general_admission', -- for future multi-tier support
  seat_info JSONB, -- for future seat selection
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLE: transactions
-- Financial records for accounting and reconciliation
-- ============================================

CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Relationships
  purchase_intent_id UUID NOT NULL REFERENCES purchase_intents(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Amounts
  gross_amount DECIMAL(10,2) NOT NULL, -- ticket price × quantity
  platform_fee DECIMAL(10,2) NOT NULL, -- HangHut's cut
  payment_processing_fee DECIMAL(10,2) NOT NULL, -- Xendit's cut
  organizer_payout DECIMAL(10,2) NOT NULL, -- Amount owed to partner
  
  -- Fee Calculation Details
  fee_percentage DECIMAL(5,2) NOT NULL, -- % applied
  fee_basis TEXT, -- 'standard', 'custom', 'promotional'
  
  -- Payment Provider Details
  xendit_transaction_id TEXT,
  
  -- Status
  status transaction_status DEFAULT 'pending',
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLE: payouts
-- Organizer payout requests and processing
-- ============================================

CREATE TABLE payouts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Relationships
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE SET NULL, -- can be multi-event payout
  
  -- Payout Details
  amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
  currency TEXT DEFAULT 'PHP',
  
  -- Bank Details (snapshot at payout time)
  bank_name TEXT NOT NULL,
  bank_account_number TEXT NOT NULL,
  bank_account_name TEXT NOT NULL,
  
  -- Xendit Disbursement
  xendit_disbursement_id TEXT UNIQUE,
  xendit_external_id TEXT UNIQUE,
  
  -- Status & Timing
  status payout_status DEFAULT 'pending_request',
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES users(id),
  processed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  
  -- Admin Notes
  admin_notes TEXT,
  rejection_reason TEXT,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLE: pricing_rules (for complex custom deals)
-- ============================================

CREATE TABLE pricing_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  
  -- Rule Details
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL, -- 'first_n_events_free', 'time_limited', 'volume_based'
  conditions JSONB NOT NULL, -- flexible rule conditions
  
  -- Applied Fee
  fee_percentage DECIMAL(5,2),
  per_ticket_fee DECIMAL(10,2),
  
  -- Validity
  active BOOLEAN DEFAULT true,
  starts_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  
  -- Audit
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES (Optimized for Scale & Performance)
-- ============================================

-- Partners
CREATE INDEX idx_partners_user_id ON partners(user_id);
CREATE INDEX idx_partners_status ON partners(status) WHERE status != 'rejected'; -- partial index
CREATE INDEX idx_partners_verified ON partners(verified) WHERE verified = true; -- active partners only

-- Events - Critical for map queries
CREATE INDEX idx_events_organizer_id ON events(organizer_id);
CREATE INDEX idx_events_status ON events(status);

-- Composite index for active events in viewport (MOST IMPORTANT for map performance)
-- Note: Can't use NOW() in index predicate, so we index all active events
CREATE INDEX idx_events_active_location ON events(latitude, longitude, start_datetime)
  WHERE status = 'active'; -- filter by datetime in query, not index

-- Partial index for sold out events
CREATE INDEX idx_events_sold_out ON events(id) WHERE status = 'sold_out';

-- Index for event type filtering
CREATE INDEX idx_events_type_datetime ON events(event_type, start_datetime)
  WHERE status = 'active';

-- Purchase Intents - High write volume
CREATE INDEX idx_purchase_intents_user_event ON purchase_intents(user_id, event_id);
CREATE INDEX idx_purchase_intents_event_status ON purchase_intents(event_id, status);

-- Critical: Find pending/expired intents for cleanup
CREATE INDEX idx_purchase_intents_expiry ON purchase_intents(expires_at, status)
  WHERE status = 'pending';

-- Xendit lookup (webhook processing)
CREATE UNIQUE INDEX idx_purchase_intents_xendit_invoice ON purchase_intents(xendit_invoice_id)
  WHERE xendit_invoice_id IS NOT NULL;
CREATE UNIQUE INDEX idx_purchase_intents_xendit_external ON purchase_intents(xendit_external_id)
  WHERE xendit_external_id IS NOT NULL;

-- Tickets - High read volume at events
CREATE INDEX idx_tickets_user_event ON tickets(user_id, event_id);
CREATE INDEX idx_tickets_event_status ON tickets(event_id, status);

-- Critical: Fast QR code lookup at venue entrance
CREATE UNIQUE INDEX idx_tickets_qr_code_hash ON tickets(qr_code) WHERE status = 'valid';

-- Find unused tickets for specific event (check-in efficiency)
CREATE INDEX idx_tickets_event_unused ON tickets(event_id, status)
  WHERE status = 'valid' AND checked_in_at IS NULL;

-- Transactions - Accounting queries
CREATE INDEX idx_transactions_partner_event ON transactions(partner_id, event_id);
CREATE INDEX idx_transactions_created_status ON transactions(created_at DESC, status);

-- Composite index for payout calculations
CREATE INDEX idx_transactions_partner_status_amount ON transactions(partner_id, status, organizer_payout)
  WHERE status = 'completed';

-- Payouts - Partner dashboard
CREATE INDEX idx_payouts_partner_status ON payouts(partner_id, status);
CREATE INDEX idx_payouts_event ON payouts(event_id) WHERE event_id IS NOT NULL;

-- Admin payout queue
CREATE INDEX idx_payouts_pending ON payouts(requested_at DESC)
  WHERE status IN ('pending_request', 'approved');

-- Pricing Rules
CREATE INDEX idx_pricing_rules_partner_active ON pricing_rules(partner_id, active)
  WHERE active = true; -- can't use NOW() in index, check expires_at in query

-- ============================================
-- MATERIALIZED VIEWS (for analytics/reporting)
-- ============================================

-- Partner performance summary (refreshed periodically)
CREATE MATERIALIZED VIEW partner_performance_summary AS
SELECT 
  p.id AS partner_id,
  p.business_name,
  COUNT(DISTINCT e.id) AS total_events,
  COALESCE(SUM(e.tickets_sold), 0) AS total_tickets_sold,
  COALESCE(SUM(t.organizer_payout), 0) AS total_earnings,
  COALESCE(SUM(t.platform_fee), 0) AS total_platform_fees,
  MAX(e.start_datetime) AS last_event_date,
  COUNT(DISTINCT e.id) FILTER (WHERE e.status = 'active') AS active_events
FROM partners p
LEFT JOIN events e ON e.organizer_id = p.id
LEFT JOIN transactions t ON t.partner_id = p.id AND t.status = 'completed'
WHERE p.status = 'approved'
GROUP BY p.id, p.business_name;

CREATE INDEX idx_partner_performance_partner_id ON partner_performance_summary(partner_id);

-- Event sales summary
CREATE MATERIALIZED VIEW event_sales_summary AS
SELECT 
  e.id AS event_id,
  e.title,
  e.start_datetime,
  e.capacity,
  e.tickets_sold,
  COUNT(DISTINCT ti.id) AS total_tickets_issued,
  COUNT(DISTINCT ti.id) FILTER (WHERE ti.status = 'used') AS tickets_used,
  COALESCE(SUM(tr.gross_amount), 0) AS total_revenue,
  COALESCE(SUM(tr.platform_fee), 0) AS platform_revenue,
  COALESCE(SUM(tr.organizer_payout), 0) AS organizer_revenue
FROM events e
LEFT JOIN tickets ti ON ti.event_id = e.id
LEFT JOIN transactions tr ON tr.event_id = e.id AND tr.status = 'completed'
GROUP BY e.id, e.title, e.start_datetime, e.capacity, e.tickets_sold;

CREATE INDEX idx_event_sales_event_id ON event_sales_summary(event_id);
CREATE INDEX idx_event_sales_datetime ON event_sales_summary(start_datetime DESC);

-- Function to refresh materialized views (run periodically via cron)
CREATE OR REPLACE FUNCTION refresh_analytics_views()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY partner_performance_summary;
  REFRESH MATERIALIZED VIEW CONCURRENTLY event_sales_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- CAPACITY MANAGEMENT (Prevent Overselling)
-- ============================================

-- Function to atomically reserve tickets (prevents race conditions)
CREATE OR REPLACE FUNCTION reserve_tickets(
  p_event_id UUID,
  p_user_id UUID,
  p_quantity INTEGER
)
RETURNS UUID AS $$
DECLARE
  v_intent_id UUID;
  v_current_sold INTEGER;
  v_capacity INTEGER;
  v_ticket_price DECIMAL(10,2);
BEGIN
  -- Lock the event row to prevent concurrent modifications
  SELECT tickets_sold, capacity, ticket_price
  INTO v_current_sold, v_capacity, v_ticket_price
  FROM events
  WHERE id = p_event_id
  FOR UPDATE; -- critical: row-level lock

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
    xendit_external_id
  ) VALUES (
    p_user_id,
    p_event_id,
    p_quantity,
    v_ticket_price,
    v_ticket_price * p_quantity,
    (v_ticket_price * p_quantity) * 0.10, -- 10% default fee
    (v_ticket_price * p_quantity) * 1.10,
    'pending',
    NOW() + INTERVAL '15 minutes',
    'intent_' || gen_random_uuid()::text
  ) RETURNING id INTO v_intent_id;

  -- Increment tickets_sold (reserves capacity)
  UPDATE events
  SET tickets_sold = tickets_sold + p_quantity,
      updated_at = NOW()
  WHERE id = p_event_id;

  RETURN v_intent_id;
END;
$$ LANGUAGE plpgsql;

-- Function to release expired reservations (run via cron job)
CREATE OR REPLACE FUNCTION release_expired_reservations()
RETURNS INTEGER AS $$
DECLARE
  v_released_count INTEGER;
BEGIN
  -- Find expired pending intents
  WITH expired_intents AS (
    SELECT id, event_id, quantity
    FROM purchase_intents
    WHERE status = 'pending'
      AND expires_at < NOW()
    FOR UPDATE SKIP LOCKED -- prevent lock contention
  ),
  released AS (
    UPDATE purchase_intents pi
    SET status = 'expired',
        updated_at = NOW()
    FROM expired_intents ei
    WHERE pi.id = ei.id
    RETURNING pi.event_id, pi.quantity
  )
  UPDATE events e
  SET tickets_sold = tickets_sold - r.quantity,
      updated_at = NOW()
  FROM released r
  WHERE e.id = r.event_id;

  GET DIAGNOSTICS v_released_count = ROW_COUNT;
  
  RETURN v_released_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PERFORMANCE MONITORING
-- ============================================

-- View to monitor high-traffic events (for scaling decisions)
CREATE OR REPLACE VIEW high_traffic_events AS
SELECT 
  e.id,
  e.title,
  e.start_datetime,
  e.capacity,
  e.tickets_sold,
  COUNT(DISTINCT pi.id) AS purchase_attempts,
  COUNT(DISTINCT pi.id) FILTER (WHERE pi.status = 'completed') AS successful_purchases,
  COUNT(DISTINCT pi.id) FILTER (WHERE pi.status = 'failed') AS failed_purchases,
  ROUND(
    COUNT(DISTINCT pi.id) FILTER (WHERE pi.status = 'completed')::NUMERIC / 
    NULLIF(COUNT(DISTINCT pi.id), 0) * 100, 
    2
  ) AS success_rate_pct
FROM events e
LEFT JOIN purchase_intents pi ON pi.event_id = e.id
WHERE e.start_datetime > NOW() - INTERVAL '30 days'
GROUP BY e.id, e.title, e.start_datetime, e.capacity, e.tickets_sold
HAVING COUNT(DISTINCT pi.id) > 50 -- events with >50 purchase attempts
ORDER BY purchase_attempts DESC;

-- ============================================
-- FUNCTIONS (Helper functions for common operations)
-- ============================================

-- Function to generate unique ticket number
CREATE OR REPLACE FUNCTION generate_ticket_number()
RETURNS TEXT AS $$
BEGIN
  RETURN 'TK-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 8));
END;
$$ LANGUAGE plpgsql;

-- Function to generate QR code data
CREATE OR REPLACE FUNCTION generate_qr_code(ticket_id UUID, event_id UUID, user_id UUID)
RETURNS TEXT AS $$
BEGIN
  -- Format: ticket_id:event_id:user_id:checksum
  RETURN ticket_id::TEXT || ':' || event_id::TEXT || ':' || user_id::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS (Auto-update timestamps)
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_partners_updated_at BEFORE UPDATE ON partners
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_purchase_intents_updated_at BEFORE UPDATE ON purchase_intents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tickets_updated_at BEFORE UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payouts_updated_at BEFORE UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY (RLS) Policies
-- ============================================

ALTER TABLE partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payouts ENABLE ROW LEVEL SECURITY;

-- Partners: Users can view their own partner profile
CREATE POLICY "Users can view own partner profile"
  ON partners FOR SELECT
  USING (auth.uid() = user_id);

-- Events: Public can browse active events
CREATE POLICY "Public can view active events"
  ON events FOR SELECT
  USING (status = 'active');

-- Events: Partners can manage their own events
CREATE POLICY "Partners can manage own events"
  ON events FOR ALL
  USING (organizer_id IN (SELECT id FROM partners WHERE user_id = auth.uid()));

-- Purchase Intents: Users can view their own purchases
CREATE POLICY "Users can view own purchase intents"
  ON purchase_intents FOR SELECT
  USING (auth.uid() = user_id);

-- Tickets: Users can view their own tickets
CREATE POLICY "Users can view own tickets"
  ON tickets FOR SELECT
  USING (auth.uid() = user_id);

-- Transactions: Partners can view their transactions
CREATE POLICY "Partners can view own transactions"
  ON transactions FOR SELECT
  USING (auth.uid() IN (SELECT user_id FROM partners WHERE id = partner_id));

-- Payouts: Partners can view their payouts
CREATE POLICY "Partners can view own payouts"
  ON payouts FOR SELECT
  USING (auth.uid() IN (SELECT user_id FROM partners WHERE id = partner_id));

-- ============================================
-- COMMENTS (Documentation)
-- ============================================

COMMENT ON TABLE partners IS 'Event organizers who can create and manage ticketed events';
COMMENT ON TABLE events IS 'Ticketed events created by verified partners';
COMMENT ON TABLE purchase_intents IS 'Tracks the purchase flow from intent to payment completion';
COMMENT ON TABLE tickets IS 'Individual tickets issued after successful payment';
COMMENT ON TABLE transactions IS 'Financial records for accounting and reconciliation';
COMMENT ON TABLE payouts IS 'Organizer payout requests and disbursement tracking';
COMMENT ON TABLE pricing_rules IS 'Custom pricing rules for specific partners (admin-configured)';
