-- 1. Update Check Constraint to include 'chat'
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
    CHECK (type IN ('like', 'comment', 'join_request', 'approved', 'system', 'invite', 'chat'));

-- 2. Create Trigger Function
CREATE OR REPLACE FUNCTION handle_new_message()
RETURNS TRIGGER AS $$
DECLARE
    recipient_id UUID;
    sender_name TEXT;
    entity_id UUID;
    chat_sub_type TEXT;
BEGIN
    -- Get Sender Name
    SELECT display_name INTO sender_name FROM public.users WHERE id = NEW.sender_id;
    IF sender_name IS NULL THEN
        sender_name := 'Someone';
    END IF;

    -- Logic for Trip Messages
    IF TG_TABLE_NAME = 'trip_messages' THEN
        entity_id := NEW.chat_id;
        chat_sub_type := 'trip';

        FOR recipient_id IN 
            SELECT user_id FROM public.trip_chat_participants 
            WHERE chat_id = entity_id AND user_id != NEW.sender_id
        LOOP
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                recipient_id, NEW.sender_id, 'chat',
                sender_name, 
                substring(NEW.content from 1 for 100), 
                entity_id,
                jsonb_build_object('chat_type', 'trip')
            );
        END LOOP;

    -- Logic for Table Messages
    ELSE
        entity_id := NEW.table_id;
        chat_sub_type := 'table';

        FOR recipient_id IN 
            SELECT user_id FROM public.table_members 
            WHERE table_id = entity_id 
              AND status IN ('approved', 'joined', 'attended') 
              AND user_id != NEW.sender_id
        LOOP
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                recipient_id, NEW.sender_id, 'chat',
                sender_name, 
                substring(NEW.content from 1 for 100), 
                entity_id,
                jsonb_build_object('chat_type', 'table')
            );
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create Triggers
DROP TRIGGER IF EXISTS on_new_table_message ON public.messages;
CREATE TRIGGER on_new_table_message
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_message();

DROP TRIGGER IF EXISTS on_new_trip_message ON public.trip_messages;
CREATE TRIGGER on_new_trip_message
    AFTER INSERT ON public.trip_messages
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_message();
