-- Elderly device: save daily check-in via SECURITY DEFINER (bypasses RLS edge cases)
CREATE OR REPLACE FUNCTION public.upsert_linked_daily_check_in(
  p_date DATE,
  p_confirmed_slots TEXT[],
  p_missed_slots TEXT[],
  p_confirmed_at JSONB DEFAULT '{}'::jsonb
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

  INSERT INTO public.daily_check_ins (
    parent_id,
    date,
    confirmed_slots,
    missed_slots,
    confirmed_at
  )
  VALUES (
    v_parent_id,
    p_date,
    COALESCE(p_confirmed_slots, '{}'),
    COALESCE(p_missed_slots, '{}'),
    COALESCE(p_confirmed_at, '{}'::jsonb)
  )
  ON CONFLICT (parent_id, date) DO UPDATE SET
    confirmed_slots = EXCLUDED.confirmed_slots,
    missed_slots = EXCLUDED.missed_slots,
    confirmed_at = EXCLUDED.confirmed_at;

  RETURN v_parent_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_linked_daily_check_in(DATE, TEXT[], TEXT[], JSONB) TO authenticated;
