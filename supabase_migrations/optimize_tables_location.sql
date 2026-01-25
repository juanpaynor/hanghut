-- Add PostGIS Geography column to public.tables for scalable spatial queries
-- This allows O(log n) distance checks using GiST index

-- 0. Ensure PostGIS is enabled (User schema suggests it might be missing)
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Add column
ALTER TABLE public.tables 
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- 2. Backfill existing data using lat/long
-- We cast to geometry then geography to ensure SRID is handled correctly
UPDATE public.tables 
SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- 3. Create GiST Index (The key to scalability)
CREATE INDEX IF NOT EXISTS idx_tables_location 
ON public.tables USING GIST (location);

-- 4. Create trigger to keep it synced
CREATE OR REPLACE FUNCTION update_table_location()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_table_location_trigger ON public.tables;
CREATE TRIGGER update_table_location_trigger
  BEFORE INSERT OR UPDATE OF latitude, longitude
  ON public.tables
  FOR EACH ROW
  EXECUTE FUNCTION update_table_location();
