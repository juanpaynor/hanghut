-- ============================================================
-- ONE-TIME FIX: Unlink transactions from rejected/failed payouts
-- 
-- Root cause: When payouts were rejected or failed, the 
-- payout_id on linked transactions was never cleared.
-- This permanently excluded those funds from available balance.
--
-- Run this ONCE to fix all currently affected partners.
-- ============================================================

-- 1. Fix event transactions
UPDATE public.transactions t
SET payout_id = NULL
FROM public.payouts p
WHERE t.payout_id = p.id
  AND p.status IN ('rejected', 'failed');

-- 2. Fix experience transactions
UPDATE public.experience_transactions t
SET payout_id = NULL
FROM public.payouts p
WHERE t.payout_id = p.id
  AND p.status IN ('rejected', 'failed');

-- Verify: Check if any stale links remain
-- SELECT t.id, t.payout_id, p.status 
-- FROM transactions t 
-- JOIN payouts p ON t.payout_id = p.id 
-- WHERE p.status IN ('rejected', 'failed');
