-- =========================================================================
-- FIX: Dynamic Names for Likes and Comments Push Notifications
-- =========================================================================
-- This script updates the database triggers that create notifications when 
-- someone likes or comments on your post, changing "Someone" to their actual name.

CREATE OR REPLACE FUNCTION public.handle_new_like()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_post_owner uuid;
  v_liker_name text;
BEGIN
  -- 1. Get the owner of the post
  SELECT user_id INTO v_post_owner 
  FROM public.posts 
  WHERE id = NEW.post_id;

  -- 2. Get the name of the person who just liked it
  SELECT display_name INTO v_liker_name 
  FROM public.users 
  WHERE id = NEW.user_id;

  -- If no name found, fallback to "Someone"
  IF v_liker_name IS NULL OR v_liker_name = '' THEN
      v_liker_name := 'Someone';
  END IF;

  -- 3. Create the notification only if they didn't like their own post
  IF FOUND AND v_post_owner != NEW.user_id THEN
    INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
    VALUES (
      v_post_owner,
      NEW.user_id,
      'like',
      v_liker_name || ' New Like',
      v_liker_name || ' liked your post', -- <--- Now dynamically says "John liked your post"
      NEW.post_id,
      jsonb_build_object('post_id', NEW.post_id)
    );
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.handle_new_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_owner_userid uuid;
  v_commenter_name text;
BEGIN
  -- 1. Get the name of the person who commented
  SELECT display_name INTO v_commenter_name 
  FROM public.users 
  WHERE id = NEW.user_id;

  IF v_commenter_name IS NULL OR v_commenter_name = '' THEN
      v_commenter_name := 'Someone';
  END IF;

  -- 2. Determine who to notify based on if it's a reply or a top-level comment
  IF NEW.parent_id IS NOT NULL THEN
    -- It's a reply to another comment
    SELECT user_id INTO v_owner_userid 
    FROM public.comments 
    WHERE id = NEW.parent_id;

    IF FOUND AND v_owner_userid != NEW.user_id THEN
      INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
      VALUES (
        v_owner_userid,
        NEW.user_id,
        'comment',
        v_commenter_name || ' replied',
        v_commenter_name || ' replied to your comment',
        NEW.post_id,
        jsonb_build_object('post_id', NEW.post_id, 'comment_id', NEW.id)
      );
    END IF;

  ELSE
    -- It's a direct comment on a post
    SELECT user_id INTO v_owner_userid 
    FROM public.posts 
    WHERE id = NEW.post_id;

    IF FOUND AND v_owner_userid != NEW.user_id THEN
      INSERT INTO public.notifications (user_id, actor_id, type, title, body, entity_id, metadata)
      VALUES (
        v_owner_userid,
        NEW.user_id,
        'comment',
        v_commenter_name || ' commented',
        v_commenter_name || ' commented on your post',
        NEW.post_id,
        jsonb_build_object('post_id', NEW.post_id, 'comment_id', NEW.id)
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
