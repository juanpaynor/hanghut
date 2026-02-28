-- Create buckets if they don't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('experiences', 'experiences', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('experience-videos', 'experience-videos', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for 'experiences' bucket

-- 1. Allow public read access
DROP POLICY IF EXISTS "Public Access Attributes" ON storage.objects;
CREATE POLICY "Public Access Attributes"
ON storage.objects FOR SELECT
USING ( bucket_id = 'experiences' );

-- 2. Allow authenticated users to upload (INSERT)
DROP POLICY IF EXISTS "Authenticated users can upload experience images" ON storage.objects;
CREATE POLICY "Authenticated users can upload experience images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'experiences' );

-- 3. Allow users to update their own files (UPDATE)
DROP POLICY IF EXISTS "Users can update their own experience images" ON storage.objects;
CREATE POLICY "Users can update their own experience images"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'experiences' AND owner = auth.uid() )
WITH CHECK ( bucket_id = 'experiences' AND owner = auth.uid() );

-- 4. Allow users to delete their own files (DELETE)
DROP POLICY IF EXISTS "Users can delete their own experience images" ON storage.objects;
CREATE POLICY "Users can delete their own experience images"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'experiences' AND owner = auth.uid() );


-- RLS Policies for 'experience-videos' bucket

-- 1. Allow public read access
DROP POLICY IF EXISTS "Public Access Videos" ON storage.objects;
CREATE POLICY "Public Access Videos"
ON storage.objects FOR SELECT
USING ( bucket_id = 'experience-videos' );

-- 2. Allow authenticated users to upload (INSERT)
DROP POLICY IF EXISTS "Authenticated users can upload experience videos" ON storage.objects;
CREATE POLICY "Authenticated users can upload experience videos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'experience-videos' );

-- 3. Allow users to update their own files (UPDATE)
DROP POLICY IF EXISTS "Users can update their own experience videos" ON storage.objects;
CREATE POLICY "Users can update their own experience videos"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'experience-videos' AND owner = auth.uid() )
WITH CHECK ( bucket_id = 'experience-videos' AND owner = auth.uid() );

-- 4. Allow users to delete their own files (DELETE)
DROP POLICY IF EXISTS "Users can delete their own experience videos" ON storage.objects;
CREATE POLICY "Users can delete their own experience videos"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'experience-videos' AND owner = auth.uid() );
