-- Fix for duplicate DM chat creation error

CREATE OR REPLACE FUNCTION public.get_or_create_dm_chat(target_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    existing_chat_id UUID;
    new_chat_id UUID;
    current_user_id UUID;
BEGIN
    current_user_id := auth.uid();
    
    -- Check for existing chat with these participants
    -- We assume direct chats only have 2 participants
    SELECT c.id INTO existing_chat_id
    FROM direct_chats c
    JOIN direct_chat_participants p1 ON c.id = p1.chat_id AND p1.user_id = current_user_id
    JOIN direct_chat_participants p2 ON c.id = p2.chat_id AND p2.user_id = target_user_id
    LIMIT 1;

    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;

    -- Create new chat
    INSERT INTO direct_chats DEFAULT VALUES RETURNING id INTO new_chat_id;

    -- Add participants
    INSERT INTO direct_chat_participants (chat_id, user_id)
    VALUES 
        (new_chat_id, current_user_id),
        (new_chat_id, target_user_id);

    RETURN new_chat_id;
END;
$function$;
