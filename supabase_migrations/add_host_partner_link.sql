-- Add partner_id to tables (links experiences to a host partner for payouts)
ALTER TABLE public.tables
ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id);

-- Add partner_id to experience_transactions (enables payout routing)
ALTER TABLE public.experience_transactions
ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id);

-- Index for fast host dashboard queries
CREATE INDEX IF NOT EXISTS idx_tables_partner_id ON public.tables(partner_id);
CREATE INDEX IF NOT EXISTS idx_experience_transactions_partner_id ON public.experience_transactions(partner_id);
