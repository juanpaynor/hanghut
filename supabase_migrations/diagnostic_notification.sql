-- DIAGNOSTIC SCRIPT FOR PUSH NOTIFICATIONS
-- Run this in Supabase SQL Editor to check configuration

-- 1. Check if pg_net is enabled
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'pg_net';

-- 2. Check if secrets table exists and has the key (DO NOT reveal values)
SELECT count(*) as secret_count 
FROM secrets.decrypted_secrets 
WHERE name = 'SUPABASE_SERVICE_ROLE_KEY';

-- 3. Dry Run Test (Manual Invoke)
-- Replace 'USER_ID_HERE' with a real user ID from your users table to test
-- This will return the request ID if successful, or error if not.
/*
SELECT net.http_post(
    url := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT value FROM secrets.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY')
    ),
    body := jsonb_build_object(
        'user_id', 'REPLACE_WITH_REAL_USER_ID', 
        'title', 'Test Notification',
        'body', 'If you see this, the connection works!'
    )
) as request_id;
*/

-- 4. Check specific trigger definition
SELECT event_object_table, trigger_name, event_manipulation, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'purchase_intents';
