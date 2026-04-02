-- ============================================================
-- Add media support to comments (images, GIFs, mentions)
-- ============================================================

-- 1. Add image_url column for photo attachments
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- 2. Add gif_url column for GIF attachments
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS gif_url TEXT;

-- 3. Add mentioned_user_ids for @mention tracking
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS mentioned_user_ids UUID[] DEFAULT '{}';
