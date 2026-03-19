-- Add custom_badge column to users table
-- Allows users to set their own badge text on their profile
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS custom_badge TEXT;
