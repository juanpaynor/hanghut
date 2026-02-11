-- FIX NOTIFICATION INFRASTRUCTURE
-- This script triggers the necessary extensions and sets up the secrets table if Vault is missing.

-- 1. Enable Networking (Required for sending push)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 2. Enable Vault (For storing keys securely)
-- Note: On some Supabase versions this is 'supabase_vault'
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- 3. Compatibility View (If secrets.decrypted_secrets is missing)
-- We create a fallback so the trigger works.
CREATE SCHEMA IF NOT EXISTS secrets;

-- Create the table if it implies a specialized setup, 
-- OR strictly rely on Vault.
-- Ideally, we alias vault.decrypted_secrets to secrets.decrypted_secrets if desired,
-- OR we just fix the trigger function to use vault.

-- Let's try to fix the Trigger Function to use the correct schema standard
-- But first, let's ensure the user can store the key.

-- Allow simple storage if Vault fails (Fallback)
CREATE TABLE IF NOT EXISTS secrets.decrypted_secrets (
    name text PRIMARY KEY,
    value text NOT NULL,
    description text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 4. INSERT THE KEY (Placeholder)
-- IMPORTANT: You must replace 'YOUR_SERVICE_KEY_HERE' with your actual service_role key.
-- You can find this in Supabase Dashboard -> Project Settings -> API.
INSERT INTO secrets.decrypted_secrets (name, value, description)
VALUES (
    'SUPABASE_SERVICE_ROLE_KEY', 
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDMzOTY0MCwiZXhwIjoyMDc5OTE1NjQwfQ.NoVlj898H0ffUHIYJVYsTfHKNq1cjEyUKvTTnn4ThEE', 
    'Service role key for invoking Edge Functions'
)
ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value;
