-- =====================================================
-- SIMPLIFIED TABLE JOIN NOTIFICATION TRIGGER (WORKING VERSION)
-- Modeled after the working purchase notification
-- =====================================================

-- Drop old function first
DROP FUNCTION IF EXISTS notify_table_join() CASCADE;
DROP FUNCTION IF EXISTS notify_table_join_simple() CASCADE;

CREATE OR REPLACE FUNCTION notify_table_join_simple()
RETURNS TRIGGER AS $$
DECLARE
  host_id UUID;
  table_name TEXT;
  joiner_name TEXT;
  joiner_photo TEXT;
BEGIN
  -- Only send notification for approved joins
  IF NEW.status != 'approved' THEN
    RETURN NEW;
  END IF;

  -- Get table host and title
  SELECT t.host_id, COALESCE(t.title, t.venue_name, 'Event')
  INTO host_id, table_name
  FROM tables t
  WHERE t.id = NEW.table_id;

  -- Don't notify if the host is joining their own table
  IF host_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Get the joiner's display name and photo
  SELECT u.display_name, up.photo_url 
  INTO joiner_name, joiner_photo
  FROM users u
  LEFT JOIN user_photos up ON up.user_id = u.id AND up.is_primary = true
  WHERE u.id = NEW.user_id;

  -- Simple call to send-push (like purchase notification)
  -- Let the Edge Function handle FCM token lookup and preferences
  PERFORM net.http_post(
    url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
    ),
    body := jsonb_build_object(
      'user_id', host_id,
      'title', joiner_name || ' joined your event! 🎉',
      'body', 'They just joined "' || table_name || '"',
      'image', joiner_photo,
      'data', jsonb_build_object(
        'type', 'table_join',
        'table_id', NEW.table_id::TEXT,
        'user_id', NEW.user_id::TEXT
      )
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Replace the triggers
DROP TRIGGER IF EXISTS on_table_participant_join ON table_participants;
CREATE TRIGGER on_table_participant_join
  AFTER INSERT ON table_participants
  FOR EACH ROW
  EXECUTE FUNCTION notify_table_join_simple();

DROP TRIGGER IF EXISTS on_table_participant_approved ON table_participants;
CREATE TRIGGER on_table_participant_approved
  AFTER UPDATE OF status ON table_participants
  FOR EACH ROW
  WHEN (OLD.status = 'pending' AND NEW.status = 'approved')
  EXECUTE FUNCTION notify_table_join_simple();
