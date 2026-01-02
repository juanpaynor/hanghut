-- Add location-based filtering with PostGIS
-- This replaces city-based filtering with 40km radius queries

-- Enable PostGIS extension for geospatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

-- Add location columns to posts table
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- Create function to update location point from lat/lng
CREATE OR REPLACE FUNCTION update_post_location()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-update location
DROP TRIGGER IF EXISTS update_post_location_trigger ON public.posts;
CREATE TRIGGER update_post_location_trigger
  BEFORE INSERT OR UPDATE OF latitude, longitude
  ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION update_post_location();

-- Create spatial index for fast radius queries
CREATE INDEX IF NOT EXISTS idx_posts_location 
ON public.posts USING GIST (location);

-- Optional: Add location to comments as well
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- Example query to find posts within 40km:
-- SELECT * FROM posts 
-- WHERE ST_DWithin(
--   location,
--   ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
--   40000  -- 40km in meters
-- );
