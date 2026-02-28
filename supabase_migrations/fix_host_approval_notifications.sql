-- ============================================================
-- Host Approval Notification Trigger
-- Sends a push notification when a partner's status changes to 'approved' or 'rejected'
-- ============================================================

CREATE OR REPLACE FUNCTION notify_host_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_user_fcm_token TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Only trigger if status has changed
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Get User's FCM Token
  SELECT fcm_token INTO v_user_fcm_token
  FROM public.users
  WHERE id = NEW.user_id;

  IF v_user_fcm_token IS NULL THEN
    RETURN NEW; -- No token to send to
  END IF;

  -- Prepare Notification Content
  IF NEW.status = 'approved' THEN
    v_title := 'Host Application Approved! 🎉';
    v_body := 'Congratulations! You can now create and host experiences on Hanghut.';
  ELSIF NEW.status = 'rejected' THEN
    v_title := 'Host Application Update';
    v_body := 'There was an update regarding your host application. Please check your email for details.';
  ELSE
    RETURN NEW; -- Ignore other status changes
  END IF;

  -- Send Notification via Edge Function
  PERFORM net.http_post(
    url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', v_title,
      'body', v_body,
      'data', jsonb_build_object(
        'type', 'host_status_update',
        'status', NEW.status
      )
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists to avoid duplication
DROP TRIGGER IF EXISTS on_partner_status_change ON public.partners;

-- Create Trigger
CREATE TRIGGER on_partner_status_change
  AFTER UPDATE OF status ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION notify_host_status_change();
