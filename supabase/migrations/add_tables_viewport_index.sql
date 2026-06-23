-- ============================================================================
-- DRAFT — review before applying.
-- Speeds up the map's "tables in viewport" query for 5k-user launch load.
--
-- WHY:
--   The app fetches map markers from the `map_ready_tables` view, filtering by
--   bounding box:
--       .gte('location_lat', minLat).lte('location_lat', maxLat)
--       .gte('location_lng', minLng).lte('location_lng', maxLng)
--   The view aliases t.latitude AS location_lat and t.longitude AS location_lng,
--   so those filters hit tables.latitude / tables.longitude.
--
--   The ONLY spatial index on `tables` today is a GIST index on the `location`
--   geography column (idx_tables_location_gist) — which this lat/lng range query
--   CANNOT use. So every viewport pan does a sequential scan over `tables`.
--   Invisible at 123 rows; a CPU killer on a 2-core Micro instance once content
--   grows and hundreds of users pan concurrently.
--
-- FIX (this migration):
--   A composite btree on (latitude, longitude). Postgres range-scans on latitude
--   and filters longitude — a large improvement over a full seqscan, with no app
--   code change required. CONCURRENTLY so it does not lock the table on a live DB.
-- ============================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tables_lat_lng
  ON public.tables (latitude, longitude);

-- ============================================================================
-- OPTIONAL, LONGER-TERM (NOT in this migration — needs an app change):
--
--   The theoretically optimal path for a 2D bounding box is ST_Intersects against
--   the existing GIST index on `location`, exactly like the events RPC already
--   does (get_events_in_viewport). That would require:
--     1) a get_tables_in_viewport(min_lat,max_lat,min_lng,max_lng) RPC, and
--     2) switching table_service.getMapReadyTables() to call it.
--
--   The btree above is the zero-risk immediate win; the RPC is the eventual ideal
--   if profiling shows the btree isn't enough at scale.
-- ============================================================================
