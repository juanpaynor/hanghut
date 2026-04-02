-- ============================================================================
-- Experience Review Categories + Host Trust Score Auto-Computation
-- ============================================================================
-- Adds category rating columns to experience_reviews and creates a trigger
-- that auto-recomputes the host's trust_score from review averages.
-- Safe to run multiple times (uses IF NOT EXISTS).
-- ============================================================================

-- 1. Create table if it doesn't exist (includes category columns)
CREATE TABLE IF NOT EXISTS public.experience_reviews (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    experience_id uuid NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text text,
    communication_rating integer CHECK (communication_rating >= 1 AND communication_rating <= 5),
    value_rating integer CHECK (value_rating >= 1 AND value_rating <= 5),
    organization_rating integer CHECK (organization_rating >= 1 AND organization_rating <= 5),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT experience_reviews_pkey PRIMARY KEY (id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_experience_reviews_experience_id ON public.experience_reviews(experience_id);
CREATE INDEX IF NOT EXISTS idx_experience_reviews_user_id ON public.experience_reviews(user_id);

-- RLS
ALTER TABLE public.experience_reviews ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  -- Only create policies if they don't exist
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'experience_reviews' AND policyname = 'Anyone can view experience reviews') THEN
    CREATE POLICY "Anyone can view experience reviews" ON public.experience_reviews FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'experience_reviews' AND policyname = 'Authenticated users can create reviews') THEN
    CREATE POLICY "Authenticated users can create reviews" ON public.experience_reviews FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'experience_reviews' AND policyname = 'Users can update their own reviews') THEN
    CREATE POLICY "Users can update their own reviews" ON public.experience_reviews FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'experience_reviews' AND policyname = 'Users can delete their own reviews') THEN
    CREATE POLICY "Users can delete their own reviews" ON public.experience_reviews FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Add category columns if table already existed without them
ALTER TABLE public.experience_reviews
ADD COLUMN IF NOT EXISTS communication_rating INTEGER CHECK (communication_rating >= 1 AND communication_rating <= 5);

ALTER TABLE public.experience_reviews
ADD COLUMN IF NOT EXISTS value_rating INTEGER CHECK (value_rating >= 1 AND value_rating <= 5);

ALTER TABLE public.experience_reviews
ADD COLUMN IF NOT EXISTS organization_rating INTEGER CHECK (organization_rating >= 1 AND organization_rating <= 5);

-- 2. Enforce one review per user per experience
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'experience_reviews_user_experience_unique'
  ) THEN
    ALTER TABLE public.experience_reviews
    ADD CONSTRAINT experience_reviews_user_experience_unique
    UNIQUE (experience_id, user_id);
    RAISE NOTICE 'Added unique constraint on (experience_id, user_id)';
  END IF;
END $$;

-- 3. Create trigger function to recompute host trust_score
CREATE OR REPLACE FUNCTION recompute_host_trust_score()
RETURNS TRIGGER AS $$
DECLARE
  v_experience_id UUID;
  v_host_id UUID;
  v_avg_rating NUMERIC;
BEGIN
  -- Determine which experience was affected
  IF TG_OP = 'DELETE' THEN
    v_experience_id := OLD.experience_id;
  ELSE
    v_experience_id := NEW.experience_id;
  END IF;

  -- Find the host of this experience
  SELECT host_id INTO v_host_id
  FROM public.tables
  WHERE id = v_experience_id;

  IF v_host_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Calculate average rating across ALL experiences by this host
  SELECT AVG(er.rating)::NUMERIC(3,2) INTO v_avg_rating
  FROM public.experience_reviews er
  JOIN public.tables t ON er.experience_id = t.id
  WHERE t.host_id = v_host_id;

  -- Update the host's trust_score
  UPDATE public.users
  SET trust_score = COALESCE(v_avg_rating, 0)
  WHERE id = v_host_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create trigger (drop first if exists)
DROP TRIGGER IF EXISTS recompute_host_trust_score_trigger ON public.experience_reviews;
CREATE TRIGGER recompute_host_trust_score_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.experience_reviews
FOR EACH ROW
EXECUTE FUNCTION recompute_host_trust_score();

-- 5. Backfill trust_score for existing hosts with reviews
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT t.host_id, AVG(er.rating)::NUMERIC(3,2) as avg_rating
    FROM public.experience_reviews er
    JOIN public.tables t ON er.experience_id = t.id
    WHERE t.host_id IS NOT NULL
    GROUP BY t.host_id
  ) LOOP
    UPDATE public.users SET trust_score = r.avg_rating WHERE id = r.host_id;
  END LOOP;
END $$;
