-- ========================================
-- COMPREHENSIVE NOTIFICATION TRIGGERS
-- Migrates all client-side notifications to database triggers
-- ========================================

-- ========================================
-- 1. POST LIKES TRIGGER
-- ========================================
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
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_new_like ON public.post_likes;
CREATE TRIGGER on_new_like
    AFTER INSERT ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_like();


-- ========================================
-- 2. COMMENTS & REPLIES TRIGGER
-- ========================================
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
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_new_comment ON public.comments;
CREATE TRIGGER on_new_comment
    AFTER INSERT ON public.comments
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_comment();


-- ========================================
-- 3. TABLE JOIN TRIGGER (Instant Join)
-- ========================================
CREATE OR REPLACE FUNCTION handle_table_join()
RETURNS TRIGGER AS $$
DECLARE
    host_id UUID;
    table_title TEXT;
BEGIN
    -- Only notify on instant join (approved status from the start)
    IF NEW.status = 'approved' AND NEW.requested_at = NEW.approved_at THEN
        -- Get table host and title
        SELECT t.host_id, t.title INTO host_id, table_title
        FROM public.tables t
        WHERE t.id = NEW.table_id;

        -- Notify host if someone else joined
        IF host_id IS NOT NULL AND host_id != NEW.user_id THEN
            INSERT INTO public.notifications (
                user_id, actor_id, type, title, body, entity_id, metadata
            ) VALUES (
                host_id,
                NEW.user_id,
                'join_request',
                'New Member Joined!',
                'A user just joined ' || COALESCE(table_title, 'your table'),
                NEW.table_id,
                jsonb_build_object('table_id', NEW.table_id)
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_table_join ON public.table_members;
CREATE TRIGGER on_table_join
    AFTER INSERT ON public.table_members
    FOR EACH ROW
    EXECUTE FUNCTION handle_table_join();


-- ========================================
-- 4. JOIN REQUEST APPROVAL TRIGGER
-- ========================================
CREATE OR REPLACE FUNCTION handle_join_approval()
RETURNS TRIGGER AS $$
BEGIN
    -- Only notify when status changes from pending to approved
    IF OLD.status = 'pending' AND NEW.status = 'approved' THEN
        INSERT INTO public.notifications (
            user_id, actor_id, type, title, body, entity_id, metadata
        ) VALUES (
            NEW.user_id,  -- Notify the member who was approved
            (SELECT host_id FROM public.tables WHERE id = NEW.table_id), -- Host is the actor
            'approved',
            'You''re in!',
            'Your request to join the table has been approved.',
            NEW.table_id,
            jsonb_build_object('table_id', NEW.table_id)
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
-- COMMENTS
-- ========================================
COMMENT ON FUNCTION handle_new_like() IS 'Automatically creates notifications when users like posts';
COMMENT ON FUNCTION handle_new_comment() IS 'Automatically creates notifications for comments and replies';
COMMENT ON FUNCTION handle_table_join() IS 'Automatically notifies hosts when users join their tables';
COMMENT ON FUNCTION handle_join_approval() IS 'Automatically notifies users when their join requests are approved';
