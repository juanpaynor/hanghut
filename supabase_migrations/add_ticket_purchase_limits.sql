-- Migration: Add Ticket Purchase Limits
-- Description: Adds min/max ticket purchase constraints per event
-- Date: 2026-01-21

-- Add min_tickets_per_purchase column
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS min_tickets_per_purchase integer DEFAULT 1;

-- Add max_tickets_per_purchase column
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS max_tickets_per_purchase integer DEFAULT 10;

-- Add check constraints
ALTER TABLE events
ADD CONSTRAINT min_tickets_positive CHECK (min_tickets_per_purchase >= 1);

ALTER TABLE events
ADD CONSTRAINT max_tickets_valid CHECK (max_tickets_per_purchase >= min_tickets_per_purchase);

ALTER TABLE events
ADD CONSTRAINT max_tickets_reasonable CHECK (max_tickets_per_purchase <= capacity);

-- Add column comments
COMMENT ON COLUMN events.min_tickets_per_purchase IS 'Minimum number of tickets a user must purchase in one order (default: 1)';
COMMENT ON COLUMN events.max_tickets_per_purchase IS 'Maximum number of tickets a user can purchase in one order (default: 10)';

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_events_ticket_limits ON events(min_tickets_per_purchase, max_tickets_per_purchase);
