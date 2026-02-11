-- ============================================================================
-- SCANNER APP BACKEND MIGRATION
-- ============================================================================
-- Purpose: Support the dedicated Scanner App with roles, check-in logic, and security.
--
-- 1. Updates `partner_role` enum with 'scanner'
-- 2. Adds `is_active` to `partner_team_members`
-- 3. Creates atomic `check_in_ticket` RPC
-- 4. Adds RLS for offline/guest list access
-- 5. Adds performance indexes
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Enum Update: Add 'scanner' role
-- ----------------------------------------------------------------------------
DO $$ 
BEGIN
  -- Check if type exists first
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'partner_role') THEN
    -- Only add logical check, Postgres doesn't support IF NOT EXISTS for enum values easily
    -- We'll catch singular error if it already exists, or strictly:
    ALTER TYPE partner_role ADD VALUE IF NOT EXISTS 'scanner';
    RAISE NOTICE 'Added scanner to partner_role';
  ELSE
    -- If type doesn't exist, create it (safe fallback)
    CREATE TYPE partner_role AS ENUM ('owner', 'manager', 'viewer', 'scanner');
    RAISE NOTICE 'Created partner_role enum';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Table Update: partner_team_members
-- ----------------------------------------------------------------------------
-- Ensure table exists before modifying
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'partner_team_members') THEN
    ALTER TABLE partner_team_members 
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
    RAISE NOTICE 'Added is_active to partner_team_members';
  ELSE
    RAISE NOTICE 'Skipping partner_team_members update: table not found';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Atomic Check-In RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_in_ticket(
    p_ticket_id UUID,
    p_event_id UUID,
    p_scanner_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ticket RECORD;
    v_attendee_name TEXT;
    v_tier_name TEXT;
    v_scanner_name TEXT;
BEGIN
    -- 1. Fetch Ticket & Validate Event
    SELECT 
        t.id, 
        t.event_id, 
        t.status, 
        t.checked_in_at,
        t.checked_in_by,
        u.display_name as guest_name,
        ti.name as tier_name
    INTO v_ticket
    FROM tickets t
    LEFT JOIN users u ON t.user_id = u.id  -- Assuming user_id links to public.users
    LEFT JOIN ticket_tiers ti ON t.tier_id = ti.id -- Assuming tier_id exists
    WHERE t.id = p_ticket_id;

    -- Handle Case: Ticket Not Found
    IF v_ticket.id IS NULL THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'TICKET_NOT_FOUND',
            'message', 'Ticket does not exist.'
        );
    END IF;

    -- Handle Case: Wrong Event
    IF v_ticket.event_id != p_event_id THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'WRONG_EVENT',
            'message', 'Ticket is for a different event.'
        );
    END IF;

    -- Handle Case: Already Checked In
    IF v_ticket.checked_in_at IS NOT NULL THEN
        -- Try to get scanner name
        SELECT display_name INTO v_scanner_name 
        FROM users WHERE id = v_ticket.checked_in_by;

        RETURN jsonb_build_object(
            'valid', false,
            'error', 'ALREADY_CHECKED_IN',
            'message', 'Ticket already used.',
            'checked_in_at', v_ticket.checked_in_at,
            'checked_in_by_name', COALESCE(v_scanner_name, 'Unknown Scanner'),
            'attendee_name', v_ticket.guest_name,
            'tier_name', v_ticket.tier_name
        );
    END IF;

    -- Handle Case: Ticket Invalid/Refunded/Cancelled
    IF v_ticket.status NOT IN ('valid', 'paid') THEN -- Adjust status check as needed
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'INVALID_STATUS',
            'message', 'Ticket status is ' || v_ticket.status,
            'status', v_ticket.status
        );
    END IF;

    -- 2. Execute Check-In
    UPDATE tickets 
    SET 
        checked_in_at = NOW(),
        checked_in_by = p_scanner_id,
        status = 'used' -- Update status to used
    WHERE id = p_ticket_id;

    RETURN jsonb_build_object(
        'valid', true,
        'attendee_name', v_ticket.guest_name,
        'tier_name', v_ticket.tier_name,
        'message', 'Check-in successful'
    );
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'valid', false,
        'error', 'INTERNAL_ERROR',
        'message', SQLERRM
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RLS Policies (Conditional)
-- ----------------------------------------------------------------------------
-- Enable RLS just in case
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;

-- Policy: Scanners can view tickets for their org's events
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Scanners can view org event tickets" ON tickets;
    
    -- NOTE: This assumes relationships exist. If specific tables are missing, this might fail runtime.
    -- We guard with basic checks, but RLS logic usually requires precise schema knowledge.
    
    -- Conceptual Policy:
    -- User is in partner_team_members 
    -- AND member.partner_id == event.organizer_id 
    -- AND member.is_active = true
    -- Note: Not filtering by role since we don't know all enum values; 
    -- being in partner_team_members is sufficient for ticket viewing
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'partner_team_members') THEN
         CREATE POLICY "Scanners can view org event tickets" ON tickets
         FOR SELECT
         TO authenticated
         USING (
           EXISTS (
             SELECT 1 FROM events e
             JOIN partner_team_members ptm ON e.organizer_id = ptm.partner_id
             WHERE e.id = tickets.event_id
             AND ptm.user_id = auth.uid()
             AND ptm.is_active = true
           )
         );
         RAISE NOTICE 'Added RLS for scanner ticket viewing';
    END IF;
END $$;

-- Policy: Team members can view their own status
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'partner_team_members') THEN
        DROP POLICY IF EXISTS "Team members can view own status" ON partner_team_members;
        
        CREATE POLICY "Team members can view own status" ON partner_team_members
        FOR SELECT
        TO authenticated
        USING (user_id = auth.uid());
        
        RAISE NOTICE 'Added RLS for team member self-view';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Performance Indexes
-- ----------------------------------------------------------------------------
-- 5. Performance Indexes
-- ----------------------------------------------------------------------------
-- Index for Guest List Search (Case insensitive, partial)
CREATE INDEX IF NOT EXISTS idx_tickets_event_guest_search 
ON tickets(event_id, guest_name) 
WHERE event_id IS NOT NULL; 
-- Note: Postgres supports simple btree on text. For ilike, we might want lower(guest_name) or pg_trgm.
-- Keeping simple for now to avoid extension checks.


DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'ticket_number') THEN
        CREATE INDEX IF NOT EXISTS idx_tickets_number ON tickets(ticket_number);
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'qr_code') THEN
        CREATE INDEX IF NOT EXISTS idx_tickets_qr_code ON tickets(qr_code);
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'partner_team_members') THEN
        CREATE INDEX IF NOT EXISTS idx_partner_members_user ON partner_team_members(user_id);
    END IF;
END $$;

COMMIT;
