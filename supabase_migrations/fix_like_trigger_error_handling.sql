-- FIX: Add exception handling to notification triggers
-- This prevents core actions (Like, Comment) from failing if the notification insertion fails
-- (e.g. due to missing public.users profile or other constraint violations).

-- 1. POST LIKES TRIGGER
CREATE OR REPLACE FUNCTION handle_new_like()
RETURNS TRIGGER AS $$
DECLARE
    post_author_id UUID;
BEGIN
    -- Get the post author
    SELECT user_id INTO post_author_id 
    FROM public.posts 
    WHERE id = NEW.post_id;

    -- Notify author if someone else liked their post
    IF post_author_id IS NOT NULL AND post_author_id != NEW.user_id THEN
        BEGIN
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                post_author_id,
                NEW.user_id,
                'like',
                'New Like',
                'Someone liked your post',
                NEW.post_id,
                jsonb_build_object('post_id', NEW.post_id)
            );
        EXCEPTION WHEN OTHERS THEN
            -- Ignore notification errors to allow the Like to succeed
            RAISE WARNING 'Failed to create like notification: %', SQLERRM;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. COMMENTS TRIGGER
CREATE OR REPLACE FUNCTION handle_new_comment()
RETURNS TRIGGER AS $$
DECLARE
    target_user_id UUID;
    notification_title TEXT;
    notification_body TEXT;
BEGIN
    -- Check if this is a reply or a top-level comment
    IF NEW.parent_id IS NOT NULL THEN
        -- REPLY: Notify the parent comment author
        SELECT user_id INTO target_user_id 
        FROM public.comments 
        WHERE id = NEW.parent_id;
        
        notification_title := 'New Reply';
        notification_body := 'Someone replied to your comment';
    ELSE
        -- TOP-LEVEL COMMENT: Notify the post author
        SELECT user_id INTO target_user_id 
        FROM public.posts 
        WHERE id = NEW.post_id;
        
        notification_title := 'New Comment';
        notification_body := substring(NEW.content from 1 for 100);
    END IF;

    -- Insert notification if target exists and is not the commenter
    IF target_user_id IS NOT NULL AND target_user_id != NEW.user_id THEN
        BEGIN
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                target_user_id,
                NEW.user_id,
                'comment',
                notification_title,
                notification_body,
                NEW.post_id,
                jsonb_build_object('post_id', NEW.post_id, 'comment_id', NEW.id)
            );
        EXCEPTION WHEN OTHERS THEN
            -- Ignore notification errors to allow the Comment to succeed
            RAISE WARNING 'Failed to create comment notification: %', SQLERRM;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
