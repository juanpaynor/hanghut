-- COMPREHENSIVE FIX for Map Marker Visibility
-- Issue: After enabling security_invoker on map_ready_tables view,
-- only the current user's tables are visible due to RLS restrictions
-- Root cause: Mixed auth.users and public.users references + incomplete RLS policies

-- CRITICAL: Ensure public.users is synced with auth.users
-- The schema shows some FKs point to auth.users, others to public.users
-- We need to ensure public.users table exists and has proper policies

-- 1. Tables: Allow EVERYONE to view all tables (no restrictions)
ALTER TABLE public.tables ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view open tables" ON public.tables;
DROP POLICY IF EXISTS "Public tables are viewable by everyone" ON public.tables;
DROP POLICY IF EXISTS "Users can view tables" ON public.tables;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.tables;
CREATE POLICY "Enable read access for all users" ON public.tables
  FOR SELECT USING (true);

-- 2. Users: Allow EVERYONE to view all user profiles
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.users;
DROP POLICY IF EXISTS "Users can view profiles" ON public.users;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.users;
CREATE POLICY "Enable read access for all users" ON public.users
  FOR SELECT USING (true);

-- 3. User Photos: Allow EVERYONE to view all photos
ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User photos are viewable by everyone" ON public.user_photos;
DROP POLICY IF EXISTS "Users can view photos" ON public.user_photos;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.user_photos;
CREATE POLICY "Enable read access for all users" ON public.user_photos
  FOR SELECT USING (true);

-- 4. Table Participants: Allow EVERYONE to view all participants
ALTER TABLE public.table_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view participants" ON public.table_participants;
DROP POLICY IF EXISTS "Users can view participants" ON public.table_participants;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.table_participants;
CREATE POLICY "Enable read access for all users" ON public.table_participants
  FOR SELECT USING (true);

-- 5. Table Members: Allow EVERYONE to view all members
ALTER TABLE public.table_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view members" ON public.table_members;
DROP POLICY IF EXISTS "Users can view members" ON public.table_members;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.table_members;
CREATE POLICY "Enable read access for all users" ON public.table_members
  FOR SELECT USING (true);

-- 6. Grant explicit SELECT permissions to ensure view can access tables
GRANT SELECT ON public.tables TO anon, authenticated;
GRANT SELECT ON public.users TO anon, authenticated;
GRANT SELECT ON public.user_photos TO anon, authenticated;
GRANT SELECT ON public.table_participants TO anon, authenticated;
GRANT SELECT ON public.table_members TO anon, authenticated;

