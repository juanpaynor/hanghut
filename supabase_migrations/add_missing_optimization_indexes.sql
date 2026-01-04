-- Add missing indexes to improve performance for Social Graph and Feed Queries

-- 1. Index for "Show me User X's posts" and Feed joins
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);

-- 2. Index for "Who follows User X?" (needed for notification counts and reverse lookups)
-- The functionality for "Who I follow" is covered by the Primary Key (follower_id, following_id)
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON public.follows(following_id);

-- 3. Index for Likes lookups ("Has User X liked this?")
-- Primary keys usually cover (post_id, user_id), so we need one for user_id to find "Posts liked by User X"
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON public.post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_comment_likes_user_id ON public.comment_likes(user_id);

-- 4. Index for Table Memberships (checking "Is User X in Table Y" is frequent)
-- Primary key usually is ID.
CREATE INDEX IF NOT EXISTS idx_table_members_user_id ON public.table_members(user_id);
CREATE INDEX IF NOT EXISTS idx_table_members_table_id ON public.table_members(table_id);

-- 5. Comments foreign keys
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON public.comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON public.comments(user_id);
