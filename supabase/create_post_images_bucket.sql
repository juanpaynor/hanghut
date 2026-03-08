-- Create "post_images" bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('post_images', 'post_images', true)
ON CONFLICT (id) DO NOTHING;

-- 1. Check and Create: Public Access for SELECT
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Public read access for post_images'
    ) THEN
        CREATE POLICY "Public read access for post_images" 
        ON storage.objects FOR SELECT 
        USING (bucket_id = 'post_images');
    END IF;
END
$$;

-- 2. Check and Create: Auth Users Upload
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Auth users can upload to post_images'
    ) THEN
        CREATE POLICY "Auth users can upload to post_images" 
        ON storage.objects FOR INSERT 
        TO authenticated 
        WITH CHECK (bucket_id = 'post_images');
    END IF;
END
$$;

-- 3. Check and Create: Auth Users Update Own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Auth users can update own objects'
    ) THEN
        CREATE POLICY "Auth users can update own objects" 
        ON storage.objects FOR UPDATE 
        TO authenticated 
        USING (bucket_id = 'post_images' AND auth.uid() = owner) 
        WITH CHECK (bucket_id = 'post_images');
    END IF;
END
$$;

-- 4. Check and Create: Auth Users Delete Own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Auth users can delete own objects'
    ) THEN
        CREATE POLICY "Auth users can delete own objects" 
        ON storage.objects FOR DELETE 
        TO authenticated 
        USING (bucket_id = 'post_images' AND auth.uid() = owner);
    END IF;
END
$$;
