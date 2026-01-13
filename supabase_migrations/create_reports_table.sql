-- Create Reporting System Table

-- Enable UUID extension if not enabled (standard)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Create Reports Table
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- If user delete account, keep report but nullify
    
    target_type TEXT NOT NULL CHECK (target_type IN ('user', 'table', 'message', 'other')),
    target_id UUID NOT NULL, -- Generic ID for the target
    
    reason_category TEXT NOT NULL, -- e.g., 'harassment', 'spam'
    description TEXT, -- User provided details
    
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
    
    metadata JSONB DEFAULT '{}'::JSONB, -- Snapshot of content
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Enable RLS
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies

-- A. INSERT: Any authenticated user can create a report
CREATE POLICY "Enable insert for authenticated users" 
ON public.reports FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = reporter_id);

-- B. SELECT: Users can see their own reports
CREATE POLICY "Enable read for reporters" 
ON public.reports FOR SELECT 
TO authenticated 
USING (auth.uid() = reporter_id);

-- C. SELECT: Admins can see all reports
-- Assuming you have an 'is_admin' function or role. 
-- For now, we'll use a placeholder or assume a specific UUID/metadata check in future.
-- PROVISIONAL: If you use service_role key, it bypasses RLS.
-- If you have an admin table:
-- USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));

-- D. UPDATE: Only admins (or system)
-- Skipping user update policy for now to prevent tampering.

-- 4. Indexing for performance
CREATE INDEX idx_reports_reporter_id ON public.reports(reporter_id);
CREATE INDEX idx_reports_target ON public.reports(target_type, target_id);
CREATE INDEX idx_reports_status ON public.reports(status);
