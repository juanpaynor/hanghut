-- Add check-in status to experience purchase intents
ALTER TABLE public.experience_purchase_intents 
ADD COLUMN IF NOT EXISTS check_in_status text DEFAULT 'pending'::text CHECK (check_in_status IN ('pending', 'checked_in', 'no_show')),
ADD COLUMN IF NOT EXISTS checked_in_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS checked_in_by uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_experience_purchase_intents_checkin_status ON public.experience_purchase_intents(check_in_status);
