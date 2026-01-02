-- Create Posts Table
CREATE TABLE IF NOT EXISTS public.posts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    content TEXT,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Access Policies for Posts
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Posts are viewable by everyone" ON public.posts;
CREATE POLICY "Posts are viewable by everyone" 
    ON public.posts FOR SELECT 
    USING (true);

DROP POLICY IF EXISTS "Users can create their own posts" ON public.posts;
CREATE POLICY "Users can create their own posts" 
    ON public.posts FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own posts" ON public.posts;
CREATE POLICY "Users can update their own posts" 
    ON public.posts FOR UPDATE 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own posts" ON public.posts;
CREATE POLICY "Users can delete their own posts" 
    ON public.posts FOR DELETE 
    USING (auth.uid() = user_id);

-- Create Comments Table (Threaded)
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE, -- For nested replies
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Access Policies for Comments
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Comments are viewable by everyone" ON public.comments;
CREATE POLICY "Comments are viewable by everyone" 
    ON public.comments FOR SELECT 
    USING (true);

DROP POLICY IF EXISTS "Users can create their own comments" ON public.comments;
CREATE POLICY "Users can create their own comments" 
    ON public.comments FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own comments" ON public.comments;
CREATE POLICY "Users can delete their own comments" 
    ON public.comments FOR DELETE 
    USING (auth.uid() = user_id);

-- Create Post Likes Table
CREATE TABLE IF NOT EXISTS public.post_likes (
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (post_id, user_id)
);

-- Access Policies for Post Likes
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Post likes are viewable by everyone" ON public.post_likes;
CREATE POLICY "Post likes are viewable by everyone" 
    ON public.post_likes FOR SELECT 
    USING (true);

DROP POLICY IF EXISTS "Users can like posts" ON public.post_likes;
CREATE POLICY "Users can like posts" 
    ON public.post_likes FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can unlike posts" ON public.post_likes;
CREATE POLICY "Users can unlike posts" 
    ON public.post_likes FOR DELETE 
    USING (auth.uid() = user_id);

-- Create Comment Likes Table
CREATE TABLE IF NOT EXISTS public.comment_likes (
    comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (comment_id, user_id)
);

-- Access Policies for Comment Likes
ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Comment likes are viewable by everyone" ON public.comment_likes;
CREATE POLICY "Comment likes are viewable by everyone" 
    ON public.comment_likes FOR SELECT 
    USING (true);

DROP POLICY IF EXISTS "Users can like comments" ON public.comment_likes;
CREATE POLICY "Users can like comments" 
    ON public.comment_likes FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can unlike comments" ON public.comment_likes;
CREATE POLICY "Users can unlike comments" 
    ON public.comment_likes FOR DELETE 
    USING (auth.uid() = user_id);

-- Create Follows Table
CREATE TABLE IF NOT EXISTS public.follows (
    follower_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    following_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (follower_id, following_id)
);

-- Access Policies for Follows
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Follows are viewable by everyone" ON public.follows;
CREATE POLICY "Follows are viewable by everyone" 
    ON public.follows FOR SELECT 
    USING (true);

DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
CREATE POLICY "Users can follow others" 
    ON public.follows FOR INSERT 
    WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS "Users can unfollow others" ON public.follows;
CREATE POLICY "Users can unfollow others" 
    ON public.follows FOR DELETE 
    USING (auth.uid() = follower_id);

-- Setup Storage Group for Social Images
-- Note: You usually need to create the bucket 'social_images' in the Supabase Dashboard if not using the API to do it.
-- Here are the policies for it:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('social_images', 'social_images', true);

-- ALLOW SELECT for everyone
DROP POLICY IF EXISTS "Social images are viewable by everyone" ON storage.objects;
CREATE POLICY "Social images are viewable by everyone"
ON storage.objects FOR SELECT
USING ( bucket_id = 'social_images' );

-- ALLOW INSERT for authenticated users
DROP POLICY IF EXISTS "Users can upload social images" ON storage.objects;
CREATE POLICY "Users can upload social images"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'social_images' AND
    auth.role() = 'authenticated'
);

-- ALLOW UPDATE/DELETE for own images
DROP POLICY IF EXISTS "Users can update own social images" ON storage.objects;
CREATE POLICY "Users can update own social images"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'social_images' AND
    auth.uid() = owner
);

DROP POLICY IF EXISTS "Users can delete own social images" ON storage.objects;
CREATE POLICY "Users can delete own social images"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'social_images' AND
    auth.uid() = owner
);
