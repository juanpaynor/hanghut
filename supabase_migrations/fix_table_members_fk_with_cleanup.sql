-- 1. Delete orphaned table_members where the table_id does not exist in tables
DELETE FROM public.table_members
WHERE table_id NOT IN (SELECT id FROM public.tables);

-- 2. Add the missing foreign key constraint
ALTER TABLE public.table_members
ADD CONSTRAINT table_members_table_id_fkey
FOREIGN KEY (table_id)
REFERENCES public.tables(id)
ON DELETE CASCADE;
