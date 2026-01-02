-- Add H3 geospatial indexing to posts table
-- H3 Resolution 7 provides ~2.5km edge hexagons
-- k-ring of 2 covers approximately 40km radius

-- Add H3 cell column to posts
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS h3_cell TEXT,
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Create index for fast H3 lookups
CREATE INDEX IF NOT EXISTS idx_posts_h3_cell ON public.posts(h3_cell);

-- Add to comments as well
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS h3_cell TEXT,
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

CREATE INDEX IF NOT EXISTS idx_comments_h3_cell ON public.comments(h3_cell);

-- Note: H3 cells will be calculated in the application layer
-- Example H3 cell: "872a1072bffffff" (Resolution 7)
