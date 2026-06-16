-- Linked elderly can read parent alarm times (RLS + RPC fallback).

CREATE POLICY "Approved join requester can view parent alarms"
  ON public.parent_alarms
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.join_requests jr ON jr.parent_id = p.id
      WHERE p.id = parent_alarms.parent_id
        AND jr.requester_id = auth.uid()
        AND jr.status = 'approved'
    )
  );

CREATE OR REPLACE FUNCTION public.get_linked_parent_alarms(p_numeric_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_result JSONB;
BEGIN
  IF p_numeric_id IS NULL OR trim(p_numeric_id) = '' THEN
    RETURN NULL;
  END IF;

  SELECT p.id
  INTO v_parent_id
  FROM public.parents p
  WHERE p.numeric_id = trim(p_numeric_id)
  LIMIT 1;

  IF v_parent_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.parents p
      WHERE p.id = v_parent_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.join_requests jr
      WHERE jr.parent_id = v_parent_id
        AND jr.requester_id = auth.uid()
        AND jr.status = 'approved'
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_settings us
      WHERE us.profile_id = auth.uid()
        AND (
          us.parent_invite_id = trim(p_numeric_id)
          OR us.parent_self_profile->>'numericId' = trim(p_numeric_id)
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.invitations i
      WHERE i.parent_id = v_parent_id
        AND i.used_by = auth.uid()
    )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'morning', COALESCE(
      (SELECT jsonb_build_object('enabled', pa.enabled, 'time', pa.time)
       FROM public.parent_alarms pa
       WHERE pa.parent_id = v_parent_id AND pa.slot = 'morning'),
      jsonb_build_object('enabled', true, 'time', '08:00')
    ),
    'afternoon', COALESCE(
      (SELECT jsonb_build_object('enabled', pa.enabled, 'time', pa.time)
       FROM public.parent_alarms pa
       WHERE pa.parent_id = v_parent_id AND pa.slot = 'afternoon'),
      jsonb_build_object('enabled', true, 'time', '13:00')
    ),
    'evening', COALESCE(
      (SELECT jsonb_build_object('enabled', pa.enabled, 'time', pa.time)
       FROM public.parent_alarms pa
       WHERE pa.parent_id = v_parent_id AND pa.slot = 'evening'),
      jsonb_build_object('enabled', false, 'time', '19:00')
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_linked_parent_alarms(TEXT) TO authenticated;
