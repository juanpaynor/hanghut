-- Create social_images storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('social_images', 'social_images', true)
ON CONFLICT (id) DO NOTHING;
