-- Add verified experience fields to tables
ALTER TABLE public.tables
ADD COLUMN IF NOT EXISTS verified_by_hanghut BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS host_bio TEXT,
ADD COLUMN IF NOT EXISTS host_avatar_url TEXT;
