-- Add username (handle) column to users table
-- This is the user's unique public handle (like Instagram's @username)

-- 1. Add the column
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username TEXT;

-- 2. Create a unique index on lowercased username for case-insensitive uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_lower 
ON public.users (LOWER(username));

-- 3. Create a helper function to generate a unique username from display_name
CREATE OR REPLACE FUNCTION generate_unique_username(base_name TEXT)
RETURNS TEXT AS $$
DECLARE
  candidate TEXT;
  suffix INT := 0;
BEGIN
  -- Sanitize: lowercase, replace spaces with underscores, strip non-alphanumeric
  candidate := LOWER(REGEXP_REPLACE(TRIM(base_name), '[^a-zA-Z0-9]', '', 'g'));
  
  -- Ensure minimum length
  IF LENGTH(candidate) < 3 THEN
    candidate := candidate || 'user';
  END IF;
  
  -- Truncate to 16 chars to leave room for suffix
  candidate := LEFT(candidate, 16);
  
  -- Check for conflicts and append numbers if needed
  WHILE EXISTS (SELECT 1 FROM public.users WHERE LOWER(username) = candidate) LOOP
    suffix := suffix + 1;
    candidate := LEFT(REGEXP_REPLACE(LOWER(TRIM(base_name)), '[^a-zA-Z0-9]', '', 'g'), 16) || suffix::TEXT;
  END LOOP;
  
  RETURN candidate;
END;
$$ LANGUAGE plpgsql;

-- 4. Auto-generate usernames for all existing users who don't have one
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id, display_name FROM public.users WHERE username IS NULL
  LOOP
    UPDATE public.users 
    SET username = generate_unique_username(COALESCE(r.display_name, 'user'))
    WHERE id = r.id;
  END LOOP;
END;
$$;

-- 5. Add a check_username_available function for the Flutter client
CREATE OR REPLACE FUNCTION check_username_available(p_username TEXT, p_exclude_user_id UUID DEFAULT NULL)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM public.users 
    WHERE LOWER(username) = LOWER(p_username)
    AND (p_exclude_user_id IS NULL OR id != p_exclude_user_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
