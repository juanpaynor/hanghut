-- Create notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.users(id) ON DELETE SET NULL, -- Changed to public.users for easier JOINs
    type TEXT NOT NULL CHECK (type IN ('like', 'comment', 'join_request', 'approved', 'system', 'invite')),
    entity_id UUID, -- Can reference tables, posts, etc. Generic ID.
    title TEXT NOT NULL,
    body TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb -- For extra data (e.g. avatar_url, route_path)
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Policies
-- 1. Users can view their own notifications
CREATE POLICY "Users can view their own notifications" 
ON public.notifications FOR SELECT 
USING (auth.uid() = user_id);

-- 2. Users can update 'is_read' on their own notifications
CREATE POLICY "Users can update their own notifications" 
ON public.notifications FOR UPDATE 
USING (auth.uid() = user_id);

-- 3. Users can insert notifications for others (e.g. Invites)
CREATE POLICY "Users can insert notifications for others (e.g. Invites)" 
ON public.notifications FOR INSERT 
WITH CHECK (auth.uid() = actor_id);


-- Scalability & Optimization
-- Composite Index for fetching "My Latest Notifications" efficiently.
CREATE INDEX idx_notifications_user_created ON public.notifications (user_id, created_at DESC);

-- Index for "Unread Count" queries
CREATE INDEX idx_notifications_user_unread ON public.notifications (user_id) WHERE is_read = FALSE;

-- Comments
COMMENT ON TABLE public.notifications IS 'Stores user notifications for the Activity Feed';
