-- Backfill Script: Create posts for EXISTING active events that don't have one yet

INSERT INTO posts (user_id, content, event_id, created_at)
SELECT 
  p.user_id,                                    -- The organizer's User ID
  '📅 Event Reminder: This is happening soon!', -- Slight variation for existing ones
  e.id,                                         -- The Event ID
  NOW()                                         -- Created just now
FROM events e
JOIN partners p ON e.organizer_id = p.id        -- Join to find the user_id
WHERE e.status = 'active'                       -- Only active events
  AND NOT EXISTS (                              -- Don't duplicate if already posted
    SELECT 1 FROM posts 
    WHERE event_id = e.id
  );

-- Output how many were inserted (for manual running)
-- SELECT count(*) FROM posts WHERE created_at = NOW();
