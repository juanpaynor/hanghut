-- Migration: Add Multiple Images Support to Events
-- Description: Adds JSONB array column to store up to 5 additional event images
-- Date: 2026-01-21

-- Add images column
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS images jsonb DEFAULT '[]'::jsonb;

-- Add column comment for documentation
COMMENT ON COLUMN events.images IS 'Array of additional event image URLs (max 5), stored as JSONB. Example: ["https://...", "https://..."]';

-- Add check constraint to limit array size to 5 images
ALTER TABLE events
ADD CONSTRAINT images_max_count CHECK (jsonb_array_length(images) <= 5);

-- Create index for faster queries on images
CREATE INDEX IF NOT EXISTS idx_events_images ON events USING gin(images);
