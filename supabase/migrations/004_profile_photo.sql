-- Profile avatar photo URL
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS photo_url TEXT;
