-- Fix: hangout (table), group, and trip chat push notifications were built
-- identically to direct messages — title = sender name, body = message — so a
-- group/hangout message looked like a 1-on-1 DM with no indication of the
-- conversation it came from.
--
-- New format for group-style chats (table / group / trip):
--   title = <hangout / group / trip name>
--   body  = "<Sender>: <message>"
-- Mentions:
--   title = "<Sender> mentioned you in <name>"
-- Direct messages are unchanged (title = sender name, body = message).

CREATE OR REPLACE FUNCTION public.handle_new_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_entity_id UUID;
    v_chat_sub_type TEXT;
    v_last_pushed_at TIMESTAMP WITH TIME ZONE;
    v_muted BOOLEAN;
    v_is_mention BOOLEAN;
    v_body TEXT;
    v_convo_name TEXT;   -- hangout / group / trip name (group-style chats)
BEGIN
    SELECT display_name INTO v_sender_name FROM public.users WHERE id = NEW.sender_id;
    IF v_sender_name IS NULL THEN v_sender_name := 'Someone'; END IF;

    IF TG_TABLE_NAME = 'direct_messages' THEN
        -- Direct messages: title = sender, body = message (unchanged).
        v_entity_id := NEW.chat_id;
        v_chat_sub_type := 'direct';
        v_body := public.friendly_message_body(NEW.content, NEW.message_type);
        FOR v_recipient_id IN
            SELECT user_id FROM public.direct_chat_participants
            WHERE chat_id = v_entity_id AND user_id != NEW.sender_id
        LOOP
            SELECT muted INTO v_muted FROM public.chat_inbox
            WHERE chat_id = v_entity_id AND user_id = v_recipient_id;
            IF COALESCE(v_muted, false) THEN CONTINUE; END IF;

            INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
            VALUES (v_recipient_id, NEW.sender_id, 'chat', v_sender_name, v_body, v_entity_id,
                    jsonb_build_object('chat_type', v_chat_sub_type));
        END LOOP;

    ELSIF TG_TABLE_NAME = 'trip_messages' THEN
        v_entity_id := NEW.chat_id;
        v_chat_sub_type := 'trip';
        v_body := public.friendly_message_body(NEW.content, NEW.message_type);

        -- Conversation name so the push reads as a group, not a DM.
        SELECT NULLIF(TRIM(destination_city), '') || ' Trip'
          INTO v_convo_name FROM public.trip_group_chats WHERE id = v_entity_id;
        IF v_convo_name IS NULL THEN v_convo_name := 'Trip Chat'; END IF;

        FOR v_recipient_id IN
            SELECT user_id FROM public.trip_chat_participants
            WHERE chat_id = v_entity_id AND user_id != NEW.sender_id
        LOOP
            SELECT muted INTO v_muted FROM public.chat_inbox
            WHERE chat_id = v_entity_id AND user_id = v_recipient_id;
            IF COALESCE(v_muted, false) THEN CONTINUE; END IF;

            SELECT created_at INTO v_last_pushed_at FROM public.notifications
            WHERE user_id = v_recipient_id AND entity_id = v_entity_id AND type = 'chat'
            ORDER BY created_at DESC LIMIT 1;
            IF v_last_pushed_at IS NULL OR (NOW() - v_last_pushed_at) > INTERVAL '30 seconds' THEN
                INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
                VALUES (v_recipient_id, NEW.sender_id, 'chat',
                        v_convo_name, v_sender_name || ': ' || v_body, v_entity_id,
                        jsonb_build_object('chat_type', v_chat_sub_type));
            END IF;
        END LOOP;

    ELSIF TG_TABLE_NAME = 'messages' THEN
        v_body := public.friendly_message_body(NEW.content, NEW.content_type);
        IF NEW.group_id IS NOT NULL THEN
            v_entity_id := NEW.group_id;
            v_chat_sub_type := 'group';

            SELECT name INTO v_convo_name FROM public.groups WHERE id = v_entity_id;
            IF v_convo_name IS NULL THEN v_convo_name := 'Group Chat'; END IF;

            FOR v_recipient_id IN
                SELECT user_id FROM public.group_members
                WHERE group_id = v_entity_id AND status = 'approved' AND user_id != NEW.sender_id
            LOOP
                SELECT muted INTO v_muted FROM public.chat_inbox
                WHERE chat_id = v_entity_id AND user_id = v_recipient_id;
                IF COALESCE(v_muted, false) THEN CONTINUE; END IF;

                v_is_mention := NEW.mentioned_user_ids IS NOT NULL
                                AND v_recipient_id = ANY(NEW.mentioned_user_ids);

                IF v_is_mention THEN
                    INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
                    VALUES (v_recipient_id, NEW.sender_id, 'mention',
                            v_sender_name || ' mentioned you in ' || v_convo_name, v_body, v_entity_id,
                            jsonb_build_object('chat_type', v_chat_sub_type, 'table_id', v_entity_id));
                ELSE
                    SELECT created_at INTO v_last_pushed_at FROM public.notifications
                    WHERE user_id = v_recipient_id AND entity_id = v_entity_id AND type IN ('chat','mention')
                    ORDER BY created_at DESC LIMIT 1;
                    IF v_last_pushed_at IS NULL OR (NOW() - v_last_pushed_at) > INTERVAL '30 seconds' THEN
                        INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
                        VALUES (v_recipient_id, NEW.sender_id, 'chat',
                                v_convo_name, v_sender_name || ': ' || v_body, v_entity_id,
                                jsonb_build_object('chat_type', v_chat_sub_type));
                    END IF;
                END IF;
            END LOOP;
        ELSE
            v_entity_id := NEW.table_id;
            v_chat_sub_type := 'table';

            SELECT title INTO v_convo_name FROM public.tables WHERE id = v_entity_id;
            IF v_convo_name IS NULL OR TRIM(v_convo_name) = '' THEN v_convo_name := 'Hangout'; END IF;

            FOR v_recipient_id IN
                SELECT user_id FROM public.table_members
                WHERE table_id = v_entity_id
                  AND status IN ('approved', 'joined', 'attended') AND user_id != NEW.sender_id
            LOOP
                SELECT muted INTO v_muted FROM public.chat_inbox
                WHERE chat_id = v_entity_id AND user_id = v_recipient_id;
                IF COALESCE(v_muted, false) THEN CONTINUE; END IF;

                v_is_mention := NEW.mentioned_user_ids IS NOT NULL
                                AND v_recipient_id = ANY(NEW.mentioned_user_ids);

                IF v_is_mention THEN
                    INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
                    VALUES (v_recipient_id, NEW.sender_id, 'mention',
                            v_sender_name || ' mentioned you in ' || v_convo_name, v_body, v_entity_id,
                            jsonb_build_object('chat_type', v_chat_sub_type, 'table_id', v_entity_id));
                ELSE
                    SELECT created_at INTO v_last_pushed_at FROM public.notifications
                    WHERE user_id = v_recipient_id AND entity_id = v_entity_id AND type IN ('chat','mention')
                    ORDER BY created_at DESC LIMIT 1;
                    IF v_last_pushed_at IS NULL OR (NOW() - v_last_pushed_at) > INTERVAL '30 seconds' THEN
                        INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
                        VALUES (v_recipient_id, NEW.sender_id, 'chat',
                                v_convo_name, v_sender_name || ': ' || v_body, v_entity_id,
                                jsonb_build_object('chat_type', v_chat_sub_type));
                    END IF;
                END IF;
            END LOOP;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
