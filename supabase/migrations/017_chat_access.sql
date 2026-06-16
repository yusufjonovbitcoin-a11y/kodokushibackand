-- Chat access + elderly contact list fixes

CREATE OR REPLACE FUNCTION public.can_access_parent(parent_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.parents p
    WHERE p.id = parent_uuid AND p.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.parents p
    JOIN public.user_settings us ON us.profile_id = auth.uid()
    WHERE p.id = parent_uuid
      AND (
        us.parent_invite_id = p.numeric_id
        OR us.parent_self_profile->>'numericId' = p.numeric_id
      )
  )
  OR EXISTS (
    SELECT 1
    FROM public.parents p
    JOIN public.invitations i ON i.parent_id = p.id
    WHERE p.id = parent_uuid
      AND i.used_by = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.join_requests jr
    JOIN public.parents p ON p.id = jr.parent_id
    WHERE p.id = parent_uuid
      AND jr.requester_id = auth.uid()
      AND jr.status = 'approved'
  )
  OR EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.parent_id = parent_uuid AND fm.profile_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_parent_owner_contact(p_numeric_id TEXT)
RETURNS TABLE (
  profile_id UUID,
  display_name TEXT,
  phone TEXT
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
  SELECT p.id, p.owner_id
  INTO v_parent_id, v_owner_id
  FROM public.parents p
  WHERE p.numeric_id = p_numeric_id;

  IF v_parent_id IS NULL OR v_owner_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT public.can_access_parent(v_parent_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    pr.id,
    COALESCE(NULLIF(TRIM(pr.name), ''), 'Family') AS display_name,
    COALESCE(pr.phone, '') AS phone
  FROM public.profiles pr
  WHERE pr.id = v_owner_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_parent_owner_contact(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_invite_linked_profiles(p_invite_code TEXT)
RETURNS TABLE (
  profile_id UUID,
  display_name TEXT,
  phone TEXT,
  linked_via TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    pr.id AS profile_id,
    COALESCE(NULLIF(TRIM(pr.name), ''), 'User') AS display_name,
    COALESCE(pr.phone, '') AS phone,
    src.linked_via
  FROM (
    SELECT p.owner_id AS pid, 'owner'::TEXT AS linked_via
    FROM public.parents p
    WHERE p.numeric_id = p_invite_code
      AND p.owner_id IS NOT NULL

    UNION

    SELECT jr.requester_id AS pid, 'join'::TEXT AS linked_via
    FROM public.join_requests jr
    WHERE jr.invite_code = p_invite_code
      AND jr.status = 'approved'
      AND jr.requester_id IS NOT NULL

    UNION

    SELECT us.profile_id AS pid, 'settings'::TEXT AS linked_via
    FROM public.user_settings us
    WHERE us.parent_invite_id = p_invite_code
       OR us.parent_self_profile->>'numericId' = p_invite_code

    UNION

    SELECT i.used_by AS pid, 'invitation'::TEXT AS linked_via
    FROM public.invitations i
    WHERE i.id = p_invite_code
      AND i.used_by IS NOT NULL

    UNION

    SELECT fm.profile_id AS pid, 'family_member'::TEXT AS linked_via
    FROM public.family_members fm
    JOIN public.parents p ON p.id = fm.parent_id
    WHERE p.numeric_id = p_invite_code
      AND fm.profile_id IS NOT NULL

    UNION

    SELECT cm.sender_id AS pid, 'chat'::TEXT AS linked_via
    FROM public.chat_messages cm
    JOIN public.parents p ON p.id = cm.parent_id
    WHERE p.numeric_id = p_invite_code
      AND cm.sender_id IS NOT NULL
      AND cm.message_type = 'text'
  ) src
  JOIN public.profiles pr ON pr.id = src.pid
  WHERE src.pid IS DISTINCT FROM auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.parents p
      WHERE p.numeric_id = p_invite_code
        AND public.can_access_parent(p.id)
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_invite_linked_profiles(TEXT) TO authenticated;
