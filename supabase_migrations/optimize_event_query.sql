-- Index for map viewport queries
-- Filters by status='active' (partial index) and covers lat/lng/time
CREATE INDEX IF NOT EXISTS idx_events_viewport 
ON events (latitude, longitude, start_datetime) 
WHERE status = 'active';

COMMENT ON INDEX idx_events_viewport IS 'Optimizes get_events_in_viewport RPC query';
