-- Enable RLS on tables
ALTER TABLE interest_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_personality ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_photos ENABLE ROW LEVEL SECURITY;

-- Allow anyone to read interest_tags (public data)
CREATE POLICY "Allow public read access to interest_tags" ON interest_tags
  FOR SELECT USING (true);

-- Allow users to read all user profiles
CREATE POLICY "Allow read access to users" ON users
  FOR SELECT USING (true);

-- Allow users to manage their own personality data
CREATE POLICY "Users can manage own personality" ON user_personality
  FOR ALL USING (user_id = (current_setting('request.jwt.claims', true)::json->>'x-hasura-user-id')::uuid);

-- Allow users to manage their own preferences
CREATE POLICY "Users can manage own preferences" ON user_preferences
  FOR ALL USING (user_id = (current_setting('request.jwt.claims', true)::json->>'x-hasura-user-id')::uuid);

-- Allow users to manage their own interests
CREATE POLICY "Users can manage own interests" ON user_interests
  FOR ALL USING (user_id = (current_setting('request.jwt.claims', true)::json->>'x-hasura-user-id')::uuid);

-- Allow users to manage their own photos
CREATE POLICY "Users can manage own photos" ON user_photos
  FOR ALL USING (user_id = (current_setting('request.jwt.claims', true)::json->>'x-hasura-user-id')::uuid);
