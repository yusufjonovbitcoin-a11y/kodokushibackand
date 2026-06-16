-- Live GPS location for elderly users (updated hourly from the app)

ALTER TABLE public.parents
  ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_location_label TEXT,
  ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.update_linked_parent_location(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_label TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_numeric_id TEXT;
  v_parent_id UUID;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'INVALID_COORDINATES';
  END IF;

  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'INVALID_COORDINATES';
  END IF;

  SELECT COALESCE(
    NULLIF(TRIM(us.parent_invite_id), ''),
    NULLIF(TRIM(us.parent_self_profile->>'numericId'), '')
  )
  INTO v_numeric_id
  FROM public.user_settings us
  WHERE us.profile_id = auth.uid();

  IF v_numeric_id IS NULL THEN
    RAISE EXCEPTION 'NOT_LINKED';
  END IF;

  SELECT p.id
  INTO v_parent_id
  FROM public.parents p
  WHERE p.numeric_id = v_numeric_id;

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION 'PARENT_NOT_FOUND';
  END IF;

  UPDATE public.parents
  SET
    current_lat = p_lat,
    current_lng = p_lng,
    current_location_label = COALESCE(NULLIF(TRIM(p_label), ''), current_location_label),
    location_updated_at = NOW()
  WHERE id = v_parent_id;

  RETURN v_parent_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_linked_parent_location(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;
