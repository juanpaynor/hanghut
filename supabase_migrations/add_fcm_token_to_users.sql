-- Add FCM Token column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Policy to allow users to update their own token
CREATE POLICY "Users can update their own fcm_token" 
ON users FOR UPDATE 
USING (auth.uid() = id) 
WITH CHECK (auth.uid() = id);
