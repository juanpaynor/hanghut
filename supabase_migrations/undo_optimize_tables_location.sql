-- UNDO Migration: optimize_tables_location.sql
-- Run this if issues arise with the geography column

-- 1. Drop Trigger
DROP TRIGGER IF EXISTS update_table_location_trigger ON public.tables;
DROP FUNCTION IF EXISTS update_table_location();

-- 2. Drop Index
DROP INDEX IF EXISTS idx_tables_location;

-- 3. Drop Column
ALTER TABLE public.tables DROP COLUMN IF EXISTS location;
