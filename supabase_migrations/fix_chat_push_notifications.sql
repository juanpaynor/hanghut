-- =====================================================
-- SIMPLIFIED CHAT NOTIFICATION TRIGGER (WORKING VERSION)
-- Modeled after the working purchase notification
-- =====================================================

-- Drop old function first
DROP FUNCTION IF EXISTS notify_chat_message() CASCADE;
DROP FUNCTION IF EXISTS notify_chat_message_simple() CASCADE;

CREATE OR REPLACE FUNCTION notify_chat_message_simple()
RETURNS TRIGGER AS $$
DECLARE
  participant_record RECORD;
  sender_name TEXT;
  sender_photo TEXT;
BEGIN
  -- Get sender's display name and photo
  SELECT u.display_name, up.photo_url 
  INTO sender_name, sender_photo
  FROM users u
  LEFT JOIN user_photos up ON up.user_id = u.id AND up.is_primary = true
  WHERE u.id = NEW.sender_id;

  -- Send notification to ALL participants (let Edge Function handle filtering)
  FOR participant_record IN
    SELECT DISTINCT p.user_id
    FROM table_participants p
    WHERE p.table_id = NEW.table_id
      AND p.user_id != NEW.sender_id
      AND p.status = 'approved'
  LOOP
    -- Simple call to send-push (like purchase notification)
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
        'image', sender_photo,
        'data', jsonb_build_object(
          'type', 'chat_message',
          'table_id', NEW.table_id::TEXT,
          'message_id', NEW.id::TEXT,
          'sender_id', NEW.sender_id::TEXT
        )
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Replace the trigger
DROP TRIGGER IF EXISTS on_chat_message_sent ON messages;
CREATE TRIGGER on_chat_message_sent
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_chat_message_simple();
