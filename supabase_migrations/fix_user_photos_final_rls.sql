-- Enable RLS on user_photos
ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;

-- Drop all existing policies to ensure a clean slate (and fix the "too tight" issue)
DROP POLICY IF EXISTS "Anyone can view user photos" ON public.user_photos;
DROP POLICY IF EXISTS "Users can insert their own photos" ON public.user_photos;
DROP POLICY IF EXISTS "Users can update their own photos" ON public.user_photos;
DROP POLICY IF EXISTS "Users can delete their own photos" ON public.user_photos;

-- 1. SELECT: Public access (everyone can see photos)
CREATE POLICY "Anyone can view user photos" 
ON public.user_photos FOR SELECT 
USING (true);

-- 2. INSERT: Users can add their own photos
CREATE POLICY "Users can insert their own photos" 
ON public.user_photos FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- 3. UPDATE: Users can update their own photos (e.g. changing is_primary, sort_order)
CREATE POLICY "Users can update their own photos" 
ON public.user_photos FOR UPDATE 
USING (auth.uid() = user_id);

-- 4. DELETE: Users can delete their own photos
CREATE POLICY "Users can delete their own photos" 
ON public.user_photos FOR DELETE 
USING (auth.uid() = user_id);
