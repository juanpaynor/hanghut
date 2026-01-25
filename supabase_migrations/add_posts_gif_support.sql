-- Add GIF support to posts table
-- This allows users to include GIFs in their social posts

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS gif_url TEXT;

COMMENT ON COLUMN posts.gif_url IS 'URL to Tenor GIF (mutually exclusive with image_urls)';
