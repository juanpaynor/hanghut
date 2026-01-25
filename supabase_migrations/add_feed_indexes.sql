-- Phase 1: Add Database Indexes for Feed Optimization
-- These indexes will dramatically speed up feed queries

-- Index for main feed query (created_at DESC ordering)
CREATE INDEX IF NOT EXISTS idx_posts_feed_created_at 
ON posts(created_at DESC, id DESC) 
WHERE visibility = 'public';

-- Index for H3 cell location filtering
CREATE INDEX IF NOT EXISTS idx_posts_h3_cell 
ON posts(h3_cell) 
WHERE h3_cell IS NOT NULL;

-- Index for user's own posts
CREATE INDEX IF NOT EXISTS idx_posts_user_id 
ON posts(user_id, created_at DESC);

-- Indexes for aggregation performance (like/comment counts)
CREATE INDEX IF NOT EXISTS idx_post_likes_post_id 
ON post_likes(post_id);

CREATE INDEX IF NOT EXISTS idx_comments_post_id 
ON comments(post_id);

-- Index for is_liked check
CREATE INDEX IF NOT EXISTS idx_post_likes_user_post 
ON post_likes(user_id, post_id);

-- Index for visibility filtering
CREATE INDEX IF NOT EXISTS idx_posts_visibility 
ON posts(visibility, created_at DESC);

COMMENT ON INDEX idx_posts_feed_created_at IS 'Optimizes main feed query ordering';
COMMENT ON INDEX idx_posts_h3_cell IS 'Speeds up location-based filtering';
COMMENT ON INDEX idx_post_likes_post_id IS 'Optimizes like count aggregation';
COMMENT ON INDEX idx_comments_post_id IS 'Optimizes comment count aggregation';
