-- Add post type, metadata, and visibility columns to posts table

-- Add post_type column with check constraint
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS post_type TEXT DEFAULT 'text' CHECK (post_type IN ('text', 'image', 'hangout'));

-- Add metadata column for storing extra details (table_id, venue, etc)
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Add visibility column
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'private'));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_posts_type ON posts(post_type);
CREATE INDEX IF NOT EXISTS idx_posts_visibility ON posts(visibility);

-- Add comment explaining columns
COMMENT ON COLUMN posts.post_type IS 'Type of post: text, image, or hangout (auto-generated)';
COMMENT ON COLUMN posts.metadata IS 'JSON metadata for special post types (e.g., table headers)';
COMMENT ON COLUMN posts.visibility IS 'Visibility scope: public, followers, or private';
