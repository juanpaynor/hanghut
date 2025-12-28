-- Migration to preserve existing table data when transitioning to new schema
-- This assumes your old tables had columns like: host_user_id, location_lat, location_lng, scheduled_at, etc.

-- First, let's check if there's an old tables structure and migrate the data
-- If you have existing tables, temporarily store them

DO $$
BEGIN
  -- Check if old columns exist and migrate data
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tables' 
    AND column_name = 'host_user_id'
  ) THEN
    -- Old schema exists, create temp backup
    CREATE TEMP TABLE tables_backup AS SELECT * FROM public.tables;
    
    -- Drop and recreate with new schema
    DROP TABLE IF EXISTS public.messages CASCADE;
    DROP TABLE IF EXISTS public.table_participants CASCADE;
    DROP TABLE IF EXISTS public.tables CASCADE;
    
    -- Recreate tables with new schema (from create_tables_schema.sql)
    CREATE TABLE public.tables (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      description TEXT,
      location_name TEXT NOT NULL,
      latitude DOUBLE PRECISION NOT NULL,
      longitude DOUBLE PRECISION NOT NULL,
      city TEXT,
      country TEXT,
      datetime TIMESTAMPTZ NOT NULL,
      max_guests INTEGER NOT NULL DEFAULT 4,
      cuisine_type TEXT,
      price_per_person NUMERIC(10, 2),
      dietary_restrictions TEXT[],
      marker_image_url TEXT,
      marker_emoji TEXT,
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'full', 'cancelled', 'completed')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    
    -- Migrate old data to new schema
    INSERT INTO public.tables (
      id,
      host_id,
      title,
      description,
      location_name,
      latitude,
      longitude,
      datetime,
      max_guests,
      cuisine_type,
      marker_image_url,
      marker_emoji,
      status,
      created_at
    )
    SELECT 
      id,
      host_user_id,
      COALESCE(title, venue_name),
      description,
      COALESCE(venue_name, 'Unknown Location'),
      location_lat,
      location_lng,
      scheduled_at,
      COALESCE(max_capacity, 4),
      activity_type,
      marker_image_url,
      marker_emoji,
      COALESCE(status, 'open'),
      COALESCE(created_at, NOW())
    FROM tables_backup;
    
    RAISE NOTICE 'Migrated % tables from old schema', (SELECT COUNT(*) FROM tables_backup);
  END IF;
END $$;
