-- Create storage bucket for profile photos
INSERT INTO storage.buckets (id, max_upload_file_size, download_expiration, min_upload_file_size, cache_control, presigned_urls_enabled)
VALUES (
  'profile-photos',
  5242880,  -- 5MB max file size
  30,       -- download expiration in seconds
  0,        -- min file size (0 = no minimum)
  'max-age=3600',  -- cache control
  true      -- enable presigned URLs
);

-- After running this SQL, go to Hasura Console to set permissions:
-- 
-- HASURA PERMISSIONS FOR user_photos TABLE:
-- =========================================
-- Data tab > public schema > user_photos > Permissions tab > 'user' role:
--
-- INSERT:
--   Row check: { "user_id": { "_eq": "X-Hasura-User-Id" } }
--   Column permissions: photo_url, is_primary, display_order
--   Column presets: user_id = X-Hasura-User-Id
--
-- SELECT:
--   Row check: { "_or": [
--     { "user_id": { "_eq": "X-Hasura-User-Id" } },
--     { "is_primary": { "_eq": true } }
--   ]}
--   All columns
--
-- UPDATE:
--   Row check: { "user_id": { "_eq": "X-Hasura-User-Id" } }
--   Columns: is_primary, display_order
--
-- DELETE:
--   Row check: { "user_id": { "_eq": "X-Hasura-User-Id" } }
