-- Fix foreign key constraints to reference public.users instead of auth.users
-- This allows PostgREST to properly resolve the relationship

-- Drop existing foreign key constraints
ALTER TABLE public.posts 
DROP CONSTRAINT IF EXISTS posts_user_id_fkey;

ALTER TABLE public.comments 
DROP CONSTRAINT IF EXISTS comments_user_id_fkey;

ALTER TABLE public.post_likes 
DROP CONSTRAINT IF EXISTS post_likes_user_id_fkey;

ALTER TABLE public.comment_likes 
DROP CONSTRAINT IF EXISTS comment_likes_user_id_fkey;

ALTER TABLE public.follows 
DROP CONSTRAINT IF EXISTS follows_follower_id_fkey,
DROP CONSTRAINT IF EXISTS follows_following_id_fkey;

-- Add new foreign key constraints referencing public.users
ALTER TABLE public.posts 
ADD CONSTRAINT posts_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.comments 
ADD CONSTRAINT comments_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.post_likes 
ADD CONSTRAINT post_likes_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.comment_likes 
ADD CONSTRAINT comment_likes_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.follows 
ADD CONSTRAINT follows_follower_id_fkey 
FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE,
ADD CONSTRAINT follows_following_id_fkey 
FOREIGN KEY (following_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
