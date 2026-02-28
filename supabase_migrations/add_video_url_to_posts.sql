-- Add video_url column to posts table if it doesn't exist
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS video_url TEXT;

-- Verify the column was added (optional, but good for confirmation)
COMMENT ON COLUMN public.posts.video_url IS 'URL for video content in the post';
