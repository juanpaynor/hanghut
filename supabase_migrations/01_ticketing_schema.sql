-- PART 1: Schema Changes (Enums & Columns)
-- RUN THIS FIRST and ensure it commits successfully before running Part 2.
-- This separates the Enum creation from its usage to avoid Postgres Error 55P04.

-- 1. Updates to Ticket Status Enum
-- We wrap in a block to ensure safe execution, but standard SQL editor run is fine.
ALTER TYPE ticket_status ADD VALUE IF NOT EXISTS 'available';
ALTER TYPE ticket_status ADD VALUE IF NOT EXISTS 'reserved';

-- 2. Relax Constraints on Tickets Table (to allow pre-minting)
ALTER TABLE tickets ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE tickets ALTER COLUMN purchase_intent_id DROP NOT NULL;
ALTER TABLE tickets ALTER COLUMN qr_code DROP NOT NULL;

-- 3. Add 'held_until' for reserved tickets
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS held_until TIMESTAMPTZ;
