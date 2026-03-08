-- 1. Add video_url to posts
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS video_url TEXT;

-- 2. Drop the existing view
DROP VIEW IF EXISTS public.map_live_stories_view;

-- 3. Recreate the view with video_url included
CREATE OR REPLACE VIEW public.map_live_stories_view AS
SELECT 
    p.event_id,
    p.table_id,
    p.external_place_id,
    p.external_place_name,
    p.latitude,
    p.longitude,
    count(p.id) as story_count,
    max(p.created_at) as latest_story_time,
    -- Get the image URL or Video URL of the most recent story at this location
    (array_agg(p.image_url ORDER BY p.created_at DESC))[1] as image_url,
    (array_agg(p.video_url ORDER BY p.created_at DESC))[1] as video_url,
    -- Get the User ID of the most recent story at this location
    (array_agg(p.user_id ORDER BY p.created_at DESC))[1] as author_id
FROM 
    public.posts p
WHERE 
    p.is_story = true 
    AND p.created_at > (NOW() - INTERVAL '24 hours')
GROUP BY 
    p.event_id, p.table_id, p.external_place_id, p.external_place_name, p.latitude, p.longitude;

-- 4. Create the social_videos bucket and allow public access
INSERT INTO storage.buckets (id, name, public) 
VALUES ('social_videos', 'social_videos', true)
ON CONFLICT (id) DO NOTHING;

-- 5. Set up RLS for social_videos
CREATE POLICY "Public Access videos" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'social_videos');

CREATE POLICY "Authenticated users can upload videos" 
ON storage.objects FOR INSERT 
WITH CHECK (
    bucket_id = 'social_videos' 
    AND auth.role() = 'authenticated'
);

CREATE POLICY "Users can edit their own videos" 
ON storage.objects FOR UPDATE 
USING (
    bucket_id = 'social_videos' 
    AND auth.uid() = owner
);

CREATE POLICY "Users can delete their own videos" 
ON storage.objects FOR DELETE 
USING (
    bucket_id = 'social_videos' 
    AND auth.uid() = owner
);
