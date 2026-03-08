-- ==========================================
-- Story Interactions Schema (RLS Policies)
-- ==========================================

-- The `post_likes` and `comments` tables already exist in the schema.
-- This script safely enables RLS and ensures the correct policies are applied
-- so users can organically Like and Comment on stories via the app UI.

-- 1. Policies for Post Likes
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    if not exists (select * from pg_policies where tablename = 'post_likes' and policyname = 'Anyone can view likes') then
        CREATE POLICY "Anyone can view likes" ON public.post_likes FOR SELECT USING (true);
    end if;

    if not exists (select * from pg_policies where tablename = 'post_likes' and policyname = 'Users can insert their own likes') then
        CREATE POLICY "Users can insert their own likes" ON public.post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
    end if;

    if not exists (select * from pg_policies where tablename = 'post_likes' and policyname = 'Users can delete their own likes') then
        CREATE POLICY "Users can delete their own likes" ON public.post_likes FOR DELETE USING (auth.uid() = user_id);
    end if;
END $$;


-- 2. Policies for Comments
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    if not exists (select * from pg_policies where tablename = 'comments' and policyname = 'Anyone can view comments') then
        CREATE POLICY "Anyone can view comments" ON public.comments FOR SELECT USING (true);
    end if;

    if not exists (select * from pg_policies where tablename = 'comments' and policyname = 'Users can insert their own comments') then
        CREATE POLICY "Users can insert their own comments" ON public.comments FOR INSERT WITH CHECK (auth.uid() = user_id);
    end if;

    if not exists (select * from pg_policies where tablename = 'comments' and policyname = 'Users can update their own comments') then
        CREATE POLICY "Users can update their own comments" ON public.comments FOR UPDATE USING (auth.uid() = user_id);
    end if;

    if not exists (select * from pg_policies where tablename = 'comments' and policyname = 'Users can delete their own comments') then
        CREATE POLICY "Users can delete their own comments" ON public.comments FOR DELETE USING (auth.uid() = user_id);
    end if;
    
    if not exists (select * from pg_policies where tablename = 'comments' and policyname = 'Post author can delete any comment on their post') then
        CREATE POLICY "Post author can delete any comment on their post" ON public.comments FOR DELETE USING (
            EXISTS (
                SELECT 1 FROM public.posts 
                WHERE id = comments.post_id AND user_id = auth.uid()
            )
        );
    end if;
END $$;
