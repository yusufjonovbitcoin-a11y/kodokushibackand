-- approve_join_request: user_settings da updated_at ustuni yo'q — tuzatish
CREATE OR REPLACE FUNCTION public.approve_join_request(p_request_id UUID)
RETURNS public.join_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.join_requests%ROWTYPE;
  v_invite_id TEXT;
BEGIN
  SELECT * INTO r
  FROM public.join_requests
  WHERE id = p_request_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found or already resolved';
  END IF;

  IF r.owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to approve this request';
  END IF;

  v_invite_id := r.invite_code;

  UPDATE public.invitations
  SET used_by = r.requester_id,
      used_at = NOW()
  WHERE (id = v_invite_id OR parent_id = r.parent_id)
    AND used_by IS NULL;

  INSERT INTO public.profiles (
    id, name, user_role, parent_app_mode, onboarding_complete, language
  )
  VALUES (
    r.requester_id, r.requester_name, 'parent', 'elderly', TRUE, r.language
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    user_role = 'parent',
    parent_app_mode = 'elderly',
    onboarding_complete = TRUE,
    language = EXCLUDED.language,
    updated_at = NOW();

  INSERT INTO public.user_settings (profile_id, parent_invite_id, parent_self_profile, setup_mode)
  VALUES (
    r.requester_id,
    v_invite_id,
    jsonb_build_object('name', r.requester_name, 'numericId', v_invite_id, 'phone', ''),
    NULL
  )
  ON CONFLICT (profile_id) DO UPDATE SET
    parent_invite_id = EXCLUDED.parent_invite_id,
    parent_self_profile = EXCLUDED.parent_self_profile,
    setup_mode = NULL;

  UPDATE public.join_requests
  SET status = 'approved',
      resolved_at = NOW(),
      resolved_by = auth.uid()
  WHERE id = p_request_id
  RETURNING * INTO r;

  BEGIN
    INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
    VALUES (
      r.requester_id,
      r.parent_id,
      'Access approved',
      'Your family member approved your request. Welcome to Mimamori!',
      1
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_join_request(UUID) TO authenticated;
