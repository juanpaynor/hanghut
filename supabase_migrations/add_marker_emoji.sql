-- Add marker_emoji column to tables table
ALTER TABLE tables
ADD COLUMN IF NOT EXISTS marker_emoji TEXT;

-- Add a comment explaining the column
COMMENT ON COLUMN tables.marker_emoji IS 'Optional emoji to display on map marker when no custom image is uploaded';
