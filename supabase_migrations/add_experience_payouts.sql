-- Add table_id to payouts to associate payouts with experiences
ALTER TABLE public.payouts
  ADD COLUMN IF NOT EXISTS table_id UUID REFERENCES public.tables(id);

-- Make event_id nullable since an experience payout won't have an event_id
ALTER TABLE public.payouts
  ALTER COLUMN event_id DROP NOT NULL;

-- Add payout_id to experience_transactions to track which transactions are paid out
ALTER TABLE public.experience_transactions
  ADD COLUMN IF NOT EXISTS payout_id UUID REFERENCES public.payouts(id);
