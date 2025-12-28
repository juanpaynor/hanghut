-- Add current_capacity column to tables
ALTER TABLE public.tables
ADD COLUMN IF NOT EXISTS current_capacity INTEGER NOT NULL DEFAULT 0 CHECK (current_capacity >= 0);

-- Create function to update current_capacity
CREATE OR REPLACE FUNCTION update_table_capacity()
RETURNS TRIGGER AS $$
BEGIN
    -- Update current_capacity based on approved/joined members
    UPDATE public.tables
    SET current_capacity = (
        SELECT COUNT(*)
        FROM public.table_members
        WHERE table_id = COALESCE(NEW.table_id, OLD.table_id)
        AND status IN ('approved', 'joined', 'attended')
    )
    WHERE id = COALESCE(NEW.table_id, OLD.table_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger on table_members to update capacity
DROP TRIGGER IF EXISTS update_table_capacity_trigger ON public.table_members;
CREATE TRIGGER update_table_capacity_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.table_members
FOR EACH ROW
EXECUTE FUNCTION update_table_capacity();

-- Initialize current_capacity for existing tables
UPDATE public.tables t
SET current_capacity = (
    SELECT COUNT(*)
    FROM public.table_members tm
    WHERE tm.table_id = t.id
    AND tm.status IN ('approved', 'joined', 'attended')
);
