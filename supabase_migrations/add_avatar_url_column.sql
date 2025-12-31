-- Add avatar_url column to users table if it doesn't exist
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS avatar_url text;

-- Optional: Add a comment
COMMENT ON COLUMN public.users.avatar_url IS 'URL to the user''s primary profile avatar';
