-- Optimized function to send push notification when someone sends a chat message
-- OPTIMIZATIONS:
-- 1. Batched query (no N+1 problem) - fetches all participants + prefs in ONE query
-- 2. Rate limiting - max 1 notification per conversation per 5 minutes
-- 3. Bulk notification sending (loops once with all data pre-fetched)
CREATE OR REPLACE FUNCTION notify_chat_message()
RETURNS TRIGGER AS $$
DECLARE
  participant_record RECORD;
  sender_name TEXT;
  rate_limit_interval INTERVAL := '5 minutes';
BEGIN
  -- Get sender's display name
  SELECT display_name INTO sender_name
  FROM users
  WHERE id = NEW.sender_id;

  -- OPTIMIZED: Fetch all eligible participants in ONE batched query
  -- This eliminates the N+1 query problem
  FOR participant_record IN
    SELECT 
      u.id as user_id,
      u.fcm_token,
      u.last_chat_notification_at
    FROM table_participants p
    INNER JOIN users u ON u.id = p.user_id
    WHERE p.table_id = NEW.table_id
      AND p.user_id != NEW.sender_id
      AND p.status = 'approved'
      -- Check notification preference in JOIN (faster than separate query)
      AND (u.notification_preferences->>'chat_messages')::boolean = true
      AND u.fcm_token IS NOT NULL
      -- RATE LIMITING: Skip if notified within last 5 minutes for this conversation
      AND (
        u.last_chat_notification_at->>NEW.table_id::text IS NULL 
        OR (u.last_chat_notification_at->>NEW.table_id::text)::timestamp + rate_limit_interval < NOW()
      )
  LOOP
    -- Send notification via Edge Function
    PERFORM net.http_post(
      url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'user_id', participant_record.user_id,
        'title', sender_name,
        'body', CASE 
          WHEN LENGTH(NEW.content) > 100 THEN SUBSTRING(NEW.content, 1, 100) || '...'
          ELSE NEW.content
        END,
        'data', jsonb_build_object(
          'type', 'chat_message',
          'table_id', NEW.table_id::TEXT,
          'message_id', NEW.id::TEXT,
          'sender_id', NEW.sender_id::TEXT
        )
      )
    );

    -- Update rate limiting timestamp for this conversation
    UPDATE users
    SET last_chat_notification_at = 
      jsonb_set(
        COALESCE(last_chat_notification_at, '{}'::jsonb),
        ARRAY[NEW.table_id::text],
        to_jsonb(NOW())
      )
    WHERE id = participant_record.user_id;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger that fires after a new message is sent
DROP TRIGGER IF EXISTS on_chat_message_sent ON messages;
CREATE TRIGGER on_chat_message_sent
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_chat_message();
