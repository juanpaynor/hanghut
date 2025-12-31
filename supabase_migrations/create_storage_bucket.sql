-- 1. Create the 'profile-photos' bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'profile-photos', 
    'profile-photos', 
    true, 
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- (Removed ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY; as it often causes permission errors and is usually enabled by default)

-- 2. Policy: Public Read Access (Anyone can view photos)
CREATE POLICY "Public Read Access"
ON storage.objects FOR SELECT
USING ( bucket_id = 'profile-photos' );

-- 3. Policy: Authenticated Upload (Users can upload their own photos)
-- We check that the folder name matches the user ID for security (userId/timestamp.jpg)
CREATE POLICY "Authenticated User Upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'profile-photos' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

-- 4. Policy: Authenticated Update (Users can replace their own photos)
CREATE POLICY "Authenticated User Update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'profile-photos' AND 
    (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
    bucket_id = 'profile-photos' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

-- 5. Policy: Authenticated Delete (Users can delete their own photos)
CREATE POLICY "Authenticated User Delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'profile-photos' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);
