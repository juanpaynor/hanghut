-- Add content_type column to messages table to distinguish text vs GIF messages
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS content_type TEXT DEFAULT 'text' CHECK (content_type IN ('text', 'gif'));

-- Update existing messages to be 'text' type
UPDATE messages SET content_type = 'text' WHERE content_type IS NULL;
