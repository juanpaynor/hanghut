-- Add missing foreign key constraint to table_members
ALTER TABLE public.table_members
ADD CONSTRAINT table_members_table_id_fkey
FOREIGN KEY (table_id)
REFERENCES public.tables(id)
ON DELETE CASCADE;
