-- Function to automatically create a feed post when an event is published
CREATE OR REPLACE FUNCTION auto_post_event_to_feed()
RETURNS TRIGGER AS $$
DECLARE
  v_organizer_user_id UUID;
  v_existing_post_id UUID;
BEGIN
  -- Condition 1: Event must be 'active'
  -- Condition 2: It must be a NEW event OR the status just changed to 'active'
  IF (NEW.status = 'active') AND (TG_OP = 'INSERT' OR OLD.status != 'active') THEN
    
    -- 1. Get the User ID of the partner/organizer
    SELECT user_id INTO v_organizer_user_id
    FROM partners
    WHERE id = NEW.organizer_id;

    -- 2. Check if a post already exists for this event (prevent duplicates)
    SELECT id INTO v_existing_post_id
    FROM posts
    WHERE event_id = NEW.id
    LIMIT 1;

    -- 3. If no post exists, create one!
    IF v_existing_post_id IS NULL AND v_organizer_user_id IS NOT NULL THEN
      INSERT INTO posts (
        user_id,
        content,
        event_id,
        created_at
      ) VALUES (
        v_organizer_user_id,
        '🎉 I just published a new event! Check it out below 👇',
        NEW.id,
        NOW()
      );
    END IF;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for INSERT (if created as active immediately)
DROP TRIGGER IF EXISTS on_event_created_active ON events;
CREATE TRIGGER on_event_created_active
  AFTER INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_post_event_to_feed();

-- Trigger for UPDATE (if changing from draft -> active)
DROP TRIGGER IF EXISTS on_event_published ON events;
CREATE TRIGGER on_event_published
  AFTER UPDATE OF status ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_post_event_to_feed();
