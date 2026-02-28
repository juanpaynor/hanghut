-- Optimized function to send push notification when someone joins a table
-- OPTIMIZATION: Batched query - fetches host info + preferences in ONE query
CREATE OR REPLACE FUNCTION notify_table_join()
RETURNS TRIGGER AS $$
DECLARE
  host_record RECORD;
  joiner_name TEXT;
  joiner_photo TEXT;
BEGIN
  -- Only send notification for confirmed joins (not pending requests)
  IF NEW.status != 'confirmed' THEN
    RETURN NEW;
  END IF;

  -- OPTIMIZED: Fetch host info + preferences in a single query
  SELECT 
    t.host_id,
    COALESCE(t.title, t.venue_name, 'Event') as table_name,
    u.notification_preferences
  INTO host_record
  FROM tables t
  INNER JOIN users u ON u.id = t.host_id
  WHERE t.id = NEW.table_id;

  -- Don't notify if the host is joining their own table
  IF host_record.host_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Check if host wants event join notifications
  IF (host_record.notification_preferences->>'event_joins')::boolean = false THEN
    RETURN NEW;
  END IF;

  -- Get the joiner's display name AND photo
  SELECT u.display_name, up.photo_url 
  INTO joiner_name, joiner_photo
  FROM users u
  LEFT JOIN user_photos up ON up.user_id = u.id AND up.is_primary = true
  WHERE u.id = NEW.user_id;

  -- Call the Edge Function to send push notification
  -- IMPORTANT: Must include Authorization header with Service Role Key for invoking Edge Functions
  PERFORM net.http_post(
    url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
    ),
    body := jsonb_build_object(
      'user_id', host_record.host_id,
      'title', joiner_name || ' joined your event! 🎉', -- Improved Copy
      'body', 'They just joined "' || host_record.table_name || '"', -- Improved Copy
      'image', joiner_photo, -- Add Image URL
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

-- Create trigger that fires after a new participant joins
DROP TRIGGER IF EXISTS on_table_participant_join ON table_participants;
CREATE TRIGGER on_table_participant_join
  AFTER INSERT ON table_participants
  FOR EACH ROW
  EXECUTE FUNCTION notify_table_join();

-- Also trigger on status update (pending -> approved)
DROP TRIGGER IF EXISTS on_table_participant_approved ON table_participants;
CREATE TRIGGER on_table_participant_approved
  AFTER UPDATE OF status ON table_participants
  FOR EACH ROW
  WHEN (OLD.status = 'pending' AND NEW.status = 'confirmed')
  EXECUTE FUNCTION notify_table_join();
