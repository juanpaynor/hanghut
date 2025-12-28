-- Storage Policies for table-markers bucket
-- Run this in Supabase SQL Editor

-- Create the bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('table-markers', 'table-markers', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload marker images for their own tables
CREATE POLICY "Users can upload marker images for their tables"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'table-markers');

-- Allow authenticated users to update marker images
CREATE POLICY "Users can update marker images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'table-markers');

-- Allow authenticated users to delete marker images
CREATE POLICY "Users can delete marker images"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'table-markers');

-- Allow public read access to all marker images (since bucket is public)
CREATE POLICY "Public can view all marker images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'table-markers');
