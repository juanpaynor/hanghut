-- Add refund tracking columns to purchase_intents
ALTER TABLE purchase_intents
ADD COLUMN IF NOT EXISTS refunded_amount NUMERIC(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMP WITH TIME ZONE;

-- Add check constraint to ensure refunded amount is non-negative
ALTER TABLE purchase_intents
ADD CONSTRAINT purchase_intents_refunded_amount_check CHECK (refunded_amount >= 0);
