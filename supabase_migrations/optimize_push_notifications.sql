-- Performance Optimizations for Push Notifications
-- This migration adds indexes and rate limiting to improve notification performance

-- 1. DATABASE INDEXES for faster lookups
-- Speed up participant queries (used in every chat notification)
CREATE INDEX IF NOT EXISTS idx_table_participants_lookup 
ON table_participants(table_id, user_id, status);

-- Speed up user preference lookups
CREATE INDEX IF NOT EXISTS idx_users_fcm_token 
ON users(id) WHERE fcm_token IS NOT NULL;

-- Speed up notification preference lookups
CREATE INDEX IF NOT EXISTS idx_users_notification_prefs 
ON users USING GIN (notification_preferences);

-- 2. RATE LIMITING - Add last notification timestamp tracking
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS last_chat_notification_at JSONB DEFAULT '{}'::jsonb;

-- Index for rate limiting checks
CREATE INDEX IF NOT EXISTS idx_users_last_notification 
ON users USING GIN (last_chat_notification_at);
