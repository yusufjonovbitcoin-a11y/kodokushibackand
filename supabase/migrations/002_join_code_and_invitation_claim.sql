-- Allow elderly / family invitees to verify a 6-digit join code without owning the parent row.
CREATE OR REPLACE FUNCTION public.verify_join_code(invite_code TEXT)
RETURNS TABLE (
  parent_id UUID,
  parent_name TEXT,
  numeric_id TEXT,
  invitation_id TEXT
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
    COALESCE(i.id, p.numeric_id) AS invitation_id
  FROM public.parents p
  LEFT JOIN public.invitations i
    ON (i.parent_id = p.id AND (i.id = invite_code OR i.id = p.numeric_id))
  WHERE p.numeric_id = invite_code
     OR i.id = invite_code
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.verify_join_code(TEXT) TO anon, authenticated;

-- Backfill invitations for parents that were created without an invitation row.
INSERT INTO public.invitations (id, created_by, parent_id, expires_at)
SELECT p.numeric_id, p.owner_id, p.id, NOW() + INTERVAL '365 days'
FROM public.parents p
WHERE NOT EXISTS (
  SELECT 1 FROM public.invitations i
  WHERE i.id = p.numeric_id OR i.parent_id = p.id
)
ON CONFLICT (id) DO NOTHING;

-- Let authenticated users claim an unused invitation (elderly / family join).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'invitations'
      AND policyname = 'Invitee can claim unused invitation'
  ) THEN
    CREATE POLICY "Invitee can claim unused invitation"
      ON public.invitations
      FOR UPDATE
      USING (used_by IS NULL)
      WITH CHECK (auth.uid() = used_by);
  END IF;
END $$;
