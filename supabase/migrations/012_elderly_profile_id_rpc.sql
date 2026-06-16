-- Family members need the elderly device profile_id to start in-app calls.

CREATE OR REPLACE FUNCTION public.get_elderly_profile_id_for_parent(p_parent_id UUID)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_numeric_id TEXT;
  v_profile_id UUID;
BEGIN
  SELECT p.numeric_id
  INTO v_numeric_id
  FROM public.parents p
  WHERE p.id = p_parent_id;

  IF v_numeric_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.parents p
      WHERE p.id = p_parent_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.family_members fm
      WHERE fm.parent_id = p_parent_id
        AND fm.profile_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.join_requests jr
      WHERE jr.invite_code = v_numeric_id
        AND jr.requester_id = auth.uid()
        AND jr.status = 'approved'
    )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT us.profile_id
  INTO v_profile_id
  FROM public.user_settings us
  WHERE us.parent_self_profile->>'numericId' = v_numeric_id
  ORDER BY us.profile_id
  LIMIT 1;

  RETURN v_profile_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_elderly_profile_id_for_parent(UUID) TO authenticated;
