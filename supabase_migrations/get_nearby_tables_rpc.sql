-- Create RPC for client-side geofencing cache
-- Allows phone to download active tables within X meters
create or replace function get_nearby_tables(
  lat double precision,
  lng double precision,
  radius_meters double precision
)
returns table (
  id uuid,
  title text,
  latitude double precision,
  longitude double precision,
  distance_meters double precision
)
language plpgsql
as $$
begin
  return query
  select
    t.id,
    t.title,
    t.latitude,
    t.longitude,
    st_distance(
      t.location,
      st_point(lng, lat)::geography
    ) as distance_meters
  from
    tables t
  where
    t.status = 'open'
    and st_dwithin(
      t.location,
      st_point(lng, lat)::geography,
      radius_meters
    )
  limit 100; -- Safety cap
end;
$$;
