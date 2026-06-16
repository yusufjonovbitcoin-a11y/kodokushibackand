-- Profiles linked to the same invite code (e.g. 600143), including ID creator.

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
  ) src
  JOIN public.profiles pr ON pr.id = src.pid
  WHERE src.pid IS DISTINCT FROM auth.uid()
    AND (
      EXISTS (
        SELECT 1
        FROM public.user_settings caller
        WHERE caller.profile_id = auth.uid()
          AND (
            caller.parent_invite_id = p_invite_code
            OR caller.parent_self_profile->>'numericId' = p_invite_code
          )
      )
      OR EXISTS (
        SELECT 1
        FROM public.join_requests caller_jr
        WHERE caller_jr.requester_id = auth.uid()
          AND caller_jr.invite_code = p_invite_code
          AND caller_jr.status = 'approved'
      )
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_invite_linked_profiles(TEXT) TO authenticated;
