-- Fix chat notification trigger to include Authorization header
-- This ensures the edge function can be invoked from database triggers

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
      AND (u.notification_preferences->>'chat_messages')::boolean = true
      AND u.fcm_token IS NOT NULL
      AND (
        u.last_chat_notification_at->>NEW.table_id::text IS NULL 
        OR (u.last_chat_notification_at->>NEW.table_id::text)::timestamp + rate_limit_interval < NOW()
      )
  LOOP
    -- Send notification via Edge Function with Authorization header
    PERFORM net.http_post(
      url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
      ),
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

    -- Update rate limiting timestamp
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

-- Recreate trigger
DROP TRIGGER IF EXISTS on_chat_message_sent ON messages;
CREATE TRIGGER on_chat_message_sent
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_chat_message();
