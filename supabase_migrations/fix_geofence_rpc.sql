-- FIX: Update get_nearby_tables to return stats required by GeofenceEngine
-- The Dart code expects 'datetime', 'current_capacity', and 'max_guests' to calculate priority.
-- Without these, the app crashes with "type 'Null' is not a subtype of type 'String'".

-- UPDATE: Changed status check from 'approved' to 'confirmed' to match Validated Production Schema.

CREATE OR REPLACE FUNCTION get_nearby_tables(
  lat double precision,
  lng double precision,
  radius_meters double precision
)
RETURNS table (
  id uuid,
  title text,
  latitude double precision,
  longitude double precision,
  distance_meters double precision,
  datetime timestamptz,      -- ADDED
  current_capacity integer,  -- ADDED
  max_guests integer         -- ADDED
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.title,
    t.latitude,
    t.longitude,
    st_distance(
      t.location,
      st_point(lng, lat)::geography
    ) as distance_meters,
    t.datetime,          -- ADDED
    t.current_capacity,  -- ADDED
    t.max_guests         -- ADDED
  FROM
    tables t
  WHERE
    t.status = 'open'
    -- Spatial Filter
    AND st_dwithin(
      t.location,
      st_point(lng, lat)::geography,
      radius_meters
    )
    -- Participation Filter (The Fix)
    AND (
      -- Is a Social Participant?
      EXISTS (
        SELECT 1 FROM table_participants tp 
        WHERE tp.table_id = t.id 
        AND tp.user_id = auth.uid() 
        AND tp.status = 'confirmed' -- FIXED: Was 'approved', Schema requires 'confirmed'
      )
      OR
      -- Is a Ticket Holder?
      -- Assumes event_id maps to tables.id in the unified schema
      EXISTS (
        SELECT 1 FROM tickets tk 
        WHERE tk.event_id = t.id 
        AND tk.user_id = auth.uid() 
        AND tk.status = 'valid'
      )
    )
  LIMIT 100;
END;
$$;
