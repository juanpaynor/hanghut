
-- Create the admin_popups table
CREATE TABLE public.admin_popups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    image_url TEXT,
    action_url TEXT,
    action_text TEXT DEFAULT 'Learn More',
    cooldown_days INTEGER, -- NULL or 0 means see once ever. e.g., 3 means reappears after 3 days.
    is_active BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS (Read-only for all users)
ALTER TABLE public.admin_popups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to active popups" 
    ON public.admin_popups 
    FOR SELECT 
    USING (is_active = true);



