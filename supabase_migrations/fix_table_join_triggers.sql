-- ========================================
-- Fix Table Join Triggers for Host Approval Flow
-- ========================================
-- Changes:
-- 1. handle_table_join: Fire on 'pending' status (join request) instead of instant join
-- 2. handle_join_approval: Also call send-push for real-time notification
-- 3. handle_join_decline: NEW - notify user when declined
-- ========================================

-- ========================================
-- 1. UPDATED: Join Request Trigger (pending)
-- Notifies host when someone requests to join
-- ========================================
CREATE OR REPLACE FUNCTION handle_table_join()
RETURNS TRIGGER AS $$
DECLARE
    v_host_id UUID;
    v_table_title TEXT;
    v_joiner_name TEXT;
BEGIN
    -- Fire when a new member is inserted with pending status
    IF NEW.status = 'pending' THEN
        -- Get table host and title
        SELECT t.host_id, t.title INTO v_host_id, v_table_title
        FROM public.tables t
        WHERE t.id = NEW.table_id;

        -- Get joiner's name
        SELECT display_name INTO v_joiner_name
        FROM public.users
        WHERE id = NEW.user_id;

        -- Notify host if someone else wants to join
        IF v_host_id IS NOT NULL AND v_host_id != NEW.user_id THEN
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                v_host_id,
                NEW.user_id,
                'join_request',
                'New Join Request',
                COALESCE(v_joiner_name, 'Someone') || ' wants to join ' || COALESCE(v_table_title, 'your table'),
                NEW.table_id,
                jsonb_build_object('table_id', NEW.table_id, 'user_id', NEW.user_id)
            );

            -- Send push notification via Edge Function
            PERFORM net.http_post(
                url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/send-push',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
                ),
                body := jsonb_build_object(
                    'user_id', v_host_id,
                    'title', 'New Join Request 🙋',
                    'body', COALESCE(v_joiner_name, 'Someone') || ' wants to join ' || COALESCE(v_table_title, 'your table'),
                    'data', jsonb_build_object('type', 'join_request', 'table_id', NEW.table_id)
                )
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_table_join ON public.table_members;
CREATE TRIGGER on_table_join
    AFTER INSERT OR UPDATE ON public.table_members
    FOR EACH ROW
    EXECUTE FUNCTION handle_table_join();


-- ========================================
-- 2. UPDATED: Join Approval Trigger
-- Notifies user when host approves + push
-- ========================================
CREATE OR REPLACE FUNCTION handle_join_approval()
RETURNS TRIGGER AS $$
DECLARE
    v_table_title TEXT;
BEGIN
    -- Only notify when status changes from pending to approved
    IF OLD.status = 'pending' AND NEW.status = 'approved' THEN
        SELECT title INTO v_table_title
        FROM public.tables WHERE id = NEW.table_id;

        INSERT INTO public.notifications (
            user_id, actor_id, type, title, body, entity_id, metadata
        ) VALUES (
            NEW.user_id,
            (SELECT host_id FROM public.tables WHERE id = NEW.table_id),
            'approved',
            'You''re in! 🎉',
            'Your request to join ' || COALESCE(v_table_title, 'the table') || ' has been approved!',
            NEW.table_id,
            jsonb_build_object('table_id', NEW.table_id)
        );

        -- Send push notification
        PERFORM net.http_post(
            url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/send-push',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
            ),
            body := jsonb_build_object(
                'user_id', NEW.user_id,
                'title', 'You''re in! 🎉',
                'body', 'Your request to join ' || COALESCE(v_table_title, 'the table') || ' has been approved!',
                'data', jsonb_build_object('type', 'approved', 'table_id', NEW.table_id)
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_join_approval ON public.table_members;
CREATE TRIGGER on_join_approval
    AFTER UPDATE ON public.table_members
    FOR EACH ROW
    EXECUTE FUNCTION handle_join_approval();


-- ========================================
-- 3. NEW: Join Decline Trigger
-- Notifies user when host declines request
-- ========================================
CREATE OR REPLACE FUNCTION handle_join_decline()
RETURNS TRIGGER AS $$
DECLARE
    v_table_title TEXT;
BEGIN
    IF OLD.status = 'pending' AND NEW.status = 'declined' THEN
        SELECT title INTO v_table_title
        FROM public.tables WHERE id = NEW.table_id;

        INSERT INTO public.notifications (
            user_id, actor_id, type, title, body, entity_id, metadata
        ) VALUES (
            NEW.user_id,
            (SELECT host_id FROM public.tables WHERE id = NEW.table_id),
            'system',
            'Request Declined',
            'Your request to join ' || COALESCE(v_table_title, 'the table') || ' was not accepted.',
            NEW.table_id,
            jsonb_build_object('table_id', NEW.table_id)
        );

        -- Send push notification
        PERFORM net.http_post(
            url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/send-push',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
            ),
            body := jsonb_build_object(
                'user_id', NEW.user_id,
                'title', 'Request Update',
                'body', 'Your request to join ' || COALESCE(v_table_title, 'the table') || ' was not accepted.',
                'data', jsonb_build_object('type', 'declined', 'table_id', NEW.table_id)
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_join_decline ON public.table_members;
CREATE TRIGGER on_join_decline
    AFTER UPDATE ON public.table_members
    FOR EACH ROW
    EXECUTE FUNCTION handle_join_decline();


-- ========================================
-- COMMENTS
-- ========================================
COMMENT ON FUNCTION handle_table_join() IS 'Notifies hosts when users request to join their tables (pending status)';
COMMENT ON FUNCTION handle_join_approval() IS 'Notifies users when their join requests are approved by host';
COMMENT ON FUNCTION handle_join_decline() IS 'Notifies users when their join requests are declined by host';
