-- Add event_id to posts table to allow "Hype Posts" / Event Attachments
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS event_id UUID REFERENCES events(id) ON DELETE SET NULL;

-- 1. Index for Foreign Key lookups (Standard practice)
-- Useful for: "Show all posts related to Event X"
CREATE INDEX IF NOT EXISTS idx_posts_event_id ON posts(event_id);

-- 2. Partial Index for Feed Performance
-- Useful for: "Get all posts that HAVE an event attached" (e.g. for filtering feed)
-- This index is smaller and faster than scanning the whole table
CREATE INDEX IF NOT EXISTS idx_posts_with_events ON posts(event_id) 
WHERE event_id IS NOT NULL;

-- 3. Composite Index for Chronological Feed of Events
-- Useful for: "Show me the latest event hype posts"
CREATE INDEX IF NOT EXISTS idx_posts_events_created_at ON posts(created_at DESC) 
WHERE event_id IS NOT NULL;

COMMENT ON COLUMN posts.event_id IS 'Link to an event. If present, the post should render an event attachment card.';
