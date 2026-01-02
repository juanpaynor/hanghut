-- Add city column to posts table for location-based filtering
-- This enables scalable city-specific feeds

-- Add city column
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS city TEXT;

-- Add index for fast city-based queries
CREATE INDEX IF NOT EXISTS idx_posts_city ON public.posts(city);

-- Add composite index for city + created_at (for paginated feeds)
CREATE INDEX IF NOT EXISTS idx_posts_city_created_at 
ON public.posts(city, created_at DESC);

-- Optional: Add city to comments for future city-based comment filtering
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS city TEXT;

CREATE INDEX IF NOT EXISTS idx_comments_city ON public.comments(city);
