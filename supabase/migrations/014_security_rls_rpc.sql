-- Security RLS, SOS RPC, elderly check-in update, join request status restrict
-- Uses SECURITY DEFINER helpers to avoid infinite recursion between parents and family_members.

CREATE OR REPLACE FUNCTION public.auth_is_parent_owner(p_parent_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.parents p
    WHERE p.id = p_parent_id
      AND p.owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.auth_is_family_member_of_parent(p_parent_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.family_members fm
    WHERE fm.parent_id = p_parent_id
      AND fm.profile_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.auth_is_parent_owner(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_is_family_member_of_parent(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_is_parent_owner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_is_family_member_of_parent(UUID) TO authenticated;

DROP POLICY IF EXISTS "Family members can view linked parent" ON public.parents;
CREATE POLICY "Family members can view linked parent"
  ON public.parents
  FOR SELECT
  USING (public.auth_is_family_member_of_parent(id));

DROP POLICY IF EXISTS "Family members can view parent family members" ON public.family_members;
CREATE POLICY "Family members can view parent family members"
  ON public.family_members
  FOR SELECT
  USING (
    public.auth_is_parent_owner(parent_id)
    OR public.auth_is_family_member_of_parent(parent_id)
  );

-- Restrict get_join_request_status to requester or owner
CREATE OR REPLACE FUNCTION public.get_join_request_status(p_request_id UUID)
RETURNS public.join_requests
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.join_requests%ROWTYPE;
BEGIN
  SELECT *
  INTO r
  FROM public.join_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  IF r.requester_id <> auth.uid() AND r.owner_id <> auth.uid() THEN
    RETURN NULL;
  END IF;

  RETURN r;
END;
$$;

REVOKE ALL ON FUNCTION public.get_join_request_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_join_request_status(UUID) TO authenticated;

-- Elderly linked user can update parent check-in status
CREATE OR REPLACE FUNCTION public.update_linked_parent_check_in_status(
  p_status TEXT,
  p_last_check_in TIMESTAMPTZ DEFAULT NULL
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
  IF p_status NOT IN ('all-good', 'caution', 'warning', 'danger') THEN
    RAISE EXCEPTION 'INVALID_STATUS';
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
    status = p_status,
    last_check_in = COALESCE(p_last_check_in, last_check_in),
    missed_alarms_today = CASE
      WHEN p_status = 'all-good' THEN 0
      ELSE missed_alarms_today
    END
  WHERE id = v_parent_id;

  RETURN v_parent_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_linked_parent_check_in_status(TEXT, TIMESTAMPTZ) TO authenticated;

-- SOS alert from linked elderly
CREATE OR REPLACE FUNCTION public.trigger_sos_alert(
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
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
  v_owner_id UUID;
  v_parent_name TEXT;
  v_requester_name TEXT;
  v_member RECORD;
BEGIN
  SELECT COALESCE(
    NULLIF(TRIM(us.parent_invite_id), ''),
    NULLIF(TRIM(us.parent_self_profile->>'numericId'), '')
  ),
  COALESCE(NULLIF(TRIM(pr.name), ''), 'Elderly user')
  INTO v_numeric_id, v_requester_name
  FROM public.user_settings us
  LEFT JOIN public.profiles pr ON pr.id = us.profile_id
  WHERE us.profile_id = auth.uid();

  IF v_numeric_id IS NULL THEN
    RAISE EXCEPTION 'NOT_LINKED';
  END IF;

  SELECT p.id, p.owner_id, p.name
  INTO v_parent_id, v_owner_id, v_parent_name
  FROM public.parents p
  WHERE p.numeric_id = v_numeric_id;

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION 'PARENT_NOT_FOUND';
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    UPDATE public.parents
    SET
      current_lat = p_lat,
      current_lng = p_lng,
      current_location_label = COALESCE(NULLIF(TRIM(p_label), ''), current_location_label),
      location_updated_at = NOW()
    WHERE id = v_parent_id;
  END IF;

  UPDATE public.parents
  SET status = 'danger'
  WHERE id = v_parent_id;

  INSERT INTO public.active_alerts (
    owner_id,
    parent_id,
    parent_name,
    time_since_last_check_in,
    action_taken
  )
  VALUES (
    v_owner_id,
    v_parent_id,
    v_parent_name,
    'SOS triggered',
    'sos'
  );

  INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
  VALUES (
    v_owner_id,
    v_parent_id,
    'SOS Emergency',
    v_requester_name || ' triggered SOS at ' || COALESCE(NULLIF(TRIM(p_label), ''), 'unknown location'),
    3
  );

  FOR v_member IN
    SELECT fm.profile_id
    FROM public.family_members fm
    WHERE fm.parent_id = v_parent_id
      AND fm.profile_id IS NOT NULL
  LOOP
    INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
    VALUES (
      v_member.profile_id,
      v_parent_id,
      'SOS Emergency',
      v_requester_name || ' triggered SOS',
      3
    );
  END LOOP;

  RETURN v_parent_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_sos_alert(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;
