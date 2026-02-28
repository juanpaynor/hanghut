-- Create experience_reviews table
CREATE TABLE public.experience_reviews (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    experience_id uuid NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT experience_reviews_pkey PRIMARY KEY (id)
);

-- Add indexes for faster query by experience and user
CREATE INDEX idx_experience_reviews_experience_id ON public.experience_reviews(experience_id);
CREATE INDEX idx_experience_reviews_user_id ON public.experience_reviews(user_id);

-- Add RLS policies
ALTER TABLE public.experience_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view experience reviews"
    ON public.experience_reviews FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create reviews"
    ON public.experience_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own reviews"
    ON public.experience_reviews FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own reviews"
    ON public.experience_reviews FOR DELETE
    USING (auth.uid() = user_id);
