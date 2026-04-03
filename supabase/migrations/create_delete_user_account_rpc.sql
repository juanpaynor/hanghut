-- RPC to delete a user's account and all associated data.
-- Called by the authenticated user themselves.
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Delete user's messages across all chat types
  DELETE FROM public.messages WHERE sender_id = _uid;
  DELETE FROM public.direct_messages WHERE sender_id = _uid;
  DELETE FROM public.trip_messages WHERE sender_id = _uid;

  -- Delete user's reactions
  DELETE FROM public.message_reactions WHERE user_id = _uid;

  -- Delete group memberships
  DELETE FROM public.group_members WHERE user_id = _uid;

  -- Delete table memberships
  DELETE FROM public.table_members WHERE user_id = _uid;

  -- Delete trip chat participations
  DELETE FROM public.trip_chat_participants WHERE user_id = _uid;

  -- Delete DM participations
  DELETE FROM public.direct_chat_participants WHERE user_id = _uid;

  -- Delete notifications (sent and received)
  DELETE FROM public.notifications WHERE user_id = _uid OR actor_id = _uid;

  -- Delete posts, comments, likes
  DELETE FROM public.post_likes WHERE user_id = _uid;
  DELETE FROM public.post_comments WHERE user_id = _uid;
  DELETE FROM public.posts WHERE user_id = _uid;

  -- Delete stories
  DELETE FROM public.stories WHERE user_id = _uid;

  -- Delete friend connections
  DELETE FROM public.friends WHERE user_id = _uid OR friend_id = _uid;

  -- Delete user profile
  DELETE FROM public.users WHERE id = _uid;

  -- Finally, delete from auth.users (SECURITY DEFINER allows this)
  DELETE FROM auth.users WHERE id = _uid;
END;
$$;

-- Grant execute to authenticated users only
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
