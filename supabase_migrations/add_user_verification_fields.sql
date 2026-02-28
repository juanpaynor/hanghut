-- Add verification fields to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS verification_method TEXT;

-- Create index for faster filtering of verified users
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON public.users(is_verified);
