-- Elderly join requests: family owner must approve before elderly account is activated.

CREATE TABLE IF NOT EXISTS public.join_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_code     TEXT NOT NULL,
  parent_id       UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  owner_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requester_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requester_name  TEXT NOT NULL,
  language        TEXT NOT NULL DEFAULT 'en',
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolved_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS join_requests_one_pending_per_parent
  ON public.join_requests (parent_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS join_requests_owner_pending_idx
  ON public.join_requests (owner_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS join_requests_requester_idx
  ON public.join_requests (requester_id, created_at DESC);

ALTER TABLE public.join_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Requester can create own join request"
  ON public.join_requests FOR INSERT
  WITH CHECK (auth.uid() = requester_id AND status = 'pending');

CREATE POLICY "Requester can read own join requests"
  ON public.join_requests FOR SELECT
  USING (auth.uid() = requester_id);

CREATE POLICY "Owner can read join requests for their parents"
  ON public.join_requests FOR SELECT
  USING (auth.uid() = owner_id);

-- verify_join_code: include owner_id for notifications
CREATE OR REPLACE FUNCTION public.verify_join_code(invite_code TEXT)
RETURNS TABLE (
  parent_id UUID,
  parent_name TEXT,
  numeric_id TEXT,
  invitation_id TEXT,
  owner_id UUID
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id AS parent_id,
    p.name AS parent_name,
    p.numeric_id,
    COALESCE(i.id, p.numeric_id) AS invitation_id,
    p.owner_id
  FROM public.parents p
  LEFT JOIN public.invitations i
    ON (i.parent_id = p.id AND (i.id = invite_code OR i.id = p.numeric_id))
  WHERE p.numeric_id = invite_code
     OR i.id = invite_code
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.verify_join_code(TEXT) TO anon, authenticated;

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

  INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
  VALUES (
    r.requester_id,
    r.parent_id,
    'Access approved',
    'Your family member approved your request. Welcome to Mimamori!',
    1
  );

  RETURN r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_join_request(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_join_request(p_request_id UUID)
RETURNS public.join_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.join_requests%ROWTYPE;
BEGIN
  SELECT * INTO r
  FROM public.join_requests
  WHERE id = p_request_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found or already resolved';
  END IF;

  IF r.owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to reject this request';
  END IF;

  UPDATE public.join_requests
  SET status = 'rejected',
      resolved_at = NOW(),
      resolved_by = auth.uid()
  WHERE id = p_request_id
  RETURNING * INTO r;

  INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
  VALUES (
    r.requester_id,
    r.parent_id,
    'Access denied',
    'Your family member declined your join request.',
    2
  );

  RETURN r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_join_request(UUID) TO authenticated;

ALTER PUBLICATION supabase_realtime ADD TABLE public.join_requests;
