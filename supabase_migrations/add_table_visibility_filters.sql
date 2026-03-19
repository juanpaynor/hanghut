-- Migration: Add visibility, filters, and invited_user_ids to tables
-- Run this against your Supabase project

-- Visibility: who can see/join this table ('public' or 'followers_only')
ALTER TABLE public.tables
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public'
  CHECK (visibility = ANY (ARRAY['public', 'followers_only']));

-- Filters: attendee preferences as JSONB
-- Example: {"gender": "women_only", "age_min": 21, "age_max": 30, "enforcement": "hard"}
ALTER TABLE public.tables
  ADD COLUMN IF NOT EXISTS filters jsonb DEFAULT '{}'::jsonb;

-- Invited users: pre-invited user IDs added by host during creation
ALTER TABLE public.tables
  ADD COLUMN IF NOT EXISTS invited_user_ids uuid[] DEFAULT '{}'::uuid[];

-- Add 'invited' to table_members status if not already present
-- (The status column uses member_status_type enum)
-- You may need to add 'invited' to the enum:
ALTER TYPE member_status_type ADD VALUE IF NOT EXISTS 'invited';
