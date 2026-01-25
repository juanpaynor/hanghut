-- Add arrival tracking columns to table_members
-- We target 'table_members' as this is the table used by ChatScreen and Triggers
-- 'arrival_status' tracks the real-time journey: 'joined' -> 'omw' -> 'arrived' -> 'verified'

ALTER TABLE public.table_members
ADD COLUMN IF NOT EXISTS arrival_status TEXT NOT NULL DEFAULT 'joined' 
  CHECK (arrival_status IN ('joined', 'omw', 'arrived', 'verified')),
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id);

-- Index for querying "Who is here?"
CREATE INDEX IF NOT EXISTS idx_table_members_arrival_status 
ON public.table_members(arrival_status);

-- Optional: Comments for documentation
COMMENT ON COLUMN public.table_members.arrival_status IS 'Real-time status: joined, omw, arrived, verified';
COMMENT ON COLUMN public.table_members.verified_by IS 'The user ID who performed the P2P verification';
