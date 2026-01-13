-- FORCE UPDATE REPORTING SCHEMA
-- The previous table structure was rigid (user/table specific). 
-- we are replacing it with a polymorphic structure (target_type + target_id) to support all entities.

DROP TABLE IF EXISTS public.reports CASCADE;

-- 1. Create Reports Table (Polymorphic)
CREATE TABLE public.reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, 
    
    target_type TEXT NOT NULL CHECK (target_type IN ('user', 'table', 'message', 'other')),
    target_id UUID NOT NULL, -- Generic ID for UserID, TableID, or MessageID
    
    reason_category TEXT NOT NULL, 
    description TEXT, 
    
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
    
    metadata JSONB DEFAULT '{}'::JSONB, 
    
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

-- 4. Indexing
CREATE INDEX idx_reports_reporter_id ON public.reports(reporter_id);
CREATE INDEX idx_reports_target ON public.reports(target_type, target_id);
