-- Add profile fields to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS occupation TEXT,
ADD COLUMN IF NOT EXISTS social_instagram TEXT,
ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

-- Add sorting to user_photos for reorderable carousel
ALTER TABLE public.user_photos
ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;

-- Comment on columns for clarity
COMMENT ON COLUMN public.users.occupation IS 'User job title or role';
COMMENT ON COLUMN public.users.social_instagram IS 'Instagram handle (without @)';
COMMENT ON COLUMN public.users.tags IS 'Array of interest/vibe tags';
COMMENT ON COLUMN public.user_photos.sort_order IS 'Order of photos in the carousel';
