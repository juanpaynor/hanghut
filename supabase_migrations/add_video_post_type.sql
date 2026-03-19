-- Add 'video' to the post_type check constraint
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_post_type_check;

ALTER TABLE posts ADD CONSTRAINT posts_post_type_check
  CHECK (post_type IN ('text', 'image', 'hangout', 'video'));
