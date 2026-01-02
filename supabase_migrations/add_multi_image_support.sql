-- Add multi-image support to posts table
-- Change image_url (TEXT) to image_urls (TEXT ARRAY)

-- Add new column
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS image_urls TEXT[];

-- Migrate existing data (convert single image_url to array)
UPDATE public.posts 
SET image_urls = ARRAY[image_url]
WHERE image_url IS NOT NULL AND image_urls IS NULL;

-- Drop old column (optional - keep for backwards compatibility or remove)
-- ALTER TABLE public.posts DROP COLUMN IF EXISTS image_url;

-- For now, keep both columns for backwards compatibility
-- Frontend will use image_urls if present, fallback to image_url
