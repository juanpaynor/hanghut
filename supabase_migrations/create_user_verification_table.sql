-- Create a table to track user verification requests
CREATE TABLE IF NOT EXISTS public.user_verifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
    id_front_url TEXT,
    id_back_url TEXT,
    selfie_url TEXT,
    admin_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Add is_verified column to users if not exists (denormalized for easy access)
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;

-- Create an RLS policy
ALTER TABLE public.user_verifications ENABLE ROW LEVEL SECURITY;

-- Users can insert their own verification request
CREATE POLICY "Users can insert their own verification"
    ON public.user_verifications FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can view their own verification request
CREATE POLICY "Users can view their own verification"
    ON public.user_verifications FOR SELECT
    USING (auth.uid() = user_id);

-- Create storage bucket for verification docs if not exists
INSERT INTO storage.buckets (id, name, public) 
VALUES ('verification-docs', 'verification-docs', false)
ON CONFLICT (id) DO NOTHING;

-- Storage Policy: Users can upload their own docs
CREATE POLICY "Users can upload their own verification docs"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'verification-docs' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);
