-- Add mentioned_user_ids column to posts table
-- Stores an array of UUIDs of users mentioned in the post content

-- 1. Add the column
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS mentioned_user_ids UUID[] DEFAULT '{}';

-- 2. Create index for efficient "posts I was mentioned in" queries
CREATE INDEX IF NOT EXISTS idx_posts_mentioned_user_ids 
ON public.posts USING gin (mentioned_user_ids);

-- 3. Create a notification trigger for mentions
-- When a post is inserted/updated with mentions, create notifications for each mentioned user
CREATE OR REPLACE FUNCTION handle_post_mentions()
RETURNS TRIGGER AS $$
DECLARE
  mentioned_id UUID;
  actor_name TEXT;
BEGIN
  -- Only process if there are mentioned users
  IF NEW.mentioned_user_ids IS NULL OR array_length(NEW.mentioned_user_ids, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  -- Get actor display name
  SELECT display_name INTO actor_name FROM public.users WHERE id = NEW.user_id;

  -- Create a notification for each mentioned user
  FOREACH mentioned_id IN ARRAY NEW.mentioned_user_ids
  LOOP
    -- Don't notify yourself
    IF mentioned_id != NEW.user_id THEN
      INSERT INTO public.notifications (
        user_id,
        actor_id,
        type,
        title,
        body,
        entity_id,
        metadata
      ) VALUES (
        mentioned_id,
        NEW.user_id,
        'mention',
        'New Mention',
        COALESCE(actor_name, 'Someone') || ' mentioned you in a post',
        NEW.id,
        jsonb_build_object('post_id', NEW.id)
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create the trigger (only on INSERT to avoid duplicate notifications on updates)
DROP TRIGGER IF EXISTS on_post_mention ON public.posts;
CREATE TRIGGER on_post_mention
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION handle_post_mentions();
