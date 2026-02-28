-- FIX: "column t.venue_name does not exist" AND "column t.ticket_price does not exist"
-- The tables table uses 'location_name', not 'venue_name'.
-- The tables table uses 'price_per_person', not 'ticket_price'.

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
  datetime timestamptz,
  current_capacity int,
  max_guests int,
  status text,
  ticket_price numeric,
  is_user_joined boolean,
  is_user_ticket_holder boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    -- FIXED: Changed t.venue_name to t.location_name
    COALESCE(t.title, t.location_name, 'Event') as title,
    t.latitude,
    t.longitude,
    st_distance(
      t.location,
      st_point(lng, lat)::geography
    ) as distance_meters,
    t.datetime,
    COALESCE(t.current_capacity, 0) as current_capacity,
    COALESCE(t.max_guests, 4) as max_guests,
    t.status,
    -- FIXED: Changed t.ticket_price to t.price_per_person
    COALESCE(t.price_per_person, 0)::numeric as ticket_price,
    -- Flag: Is user already joined?
    EXISTS (
      SELECT 1 FROM table_participants tp 
      WHERE tp.table_id = t.id 
        AND tp.user_id = auth.uid() 
        AND tp.status = 'confirmed'
    ) as is_user_joined,
    -- Flag: Does user have tickets?
    EXISTS (
      SELECT 1 FROM tickets tk 
      WHERE tk.event_id = t.id 
        AND tk.user_id = auth.uid() 
        AND tk.status = 'valid'
    ) as is_user_ticket_holder
  FROM
    tables t
  WHERE
    t.status = 'open'
    -- Spatial Filter: Within radius
    AND st_dwithin(
      t.location,
      st_point(lng, lat)::geography,
      radius_meters
    )
    -- Capacity Filter: NOT FULL
    AND COALESCE(t.current_capacity, 0) < COALESCE(t.max_guests, 4)
    -- Time Filter: Event hasn't ended yet
    AND t.datetime > NOW()
  ORDER BY distance_meters ASC
  LIMIT 100;
END;
$$;
