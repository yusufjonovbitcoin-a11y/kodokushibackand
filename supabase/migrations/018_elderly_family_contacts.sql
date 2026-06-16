-- Elderly Messages: show the family member (child) who created/approved the parent link

CREATE OR REPLACE FUNCTION public.get_elderly_family_contacts(p_invite_code TEXT)
RETURNS TABLE (
  profile_id UUID,
  display_name TEXT,
  phone TEXT,
  linked_via TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_owner_id UUID;
BEGIN
  IF NULLIF(TRIM(p_invite_code), '') IS NULL THEN
    RETURN;
  END IF;

  SELECT p.id, p.owner_id
  INTO v_parent_id, v_owner_id
  FROM public.parents p
  WHERE p.numeric_id = p_invite_code;

  IF v_parent_id IS NULL OR v_owner_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.user_settings us
      WHERE us.profile_id = auth.uid()
        AND (
          us.parent_invite_id = p_invite_code
          OR us.parent_self_profile->>'numericId' = p_invite_code
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.join_requests jr
      WHERE jr.invite_code = p_invite_code
        AND jr.status = 'approved'
        AND jr.requester_id = auth.uid()
    )
    OR public.can_access_parent(v_parent_id)
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    pr.id,
    COALESCE(NULLIF(TRIM(pr.name), ''), 'Family member') AS display_name,
    COALESCE(pr.phone, '') AS phone,
    'owner'::TEXT AS linked_via
  FROM public.profiles pr
  WHERE pr.id = v_owner_id
    AND pr.id IS DISTINCT FROM auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_elderly_family_contacts(TEXT) TO authenticated;
