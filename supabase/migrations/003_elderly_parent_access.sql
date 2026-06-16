-- Allow elderly users (linked via invite code) to read their parent row and alarms.

CREATE POLICY "Linked elderly can view parent"
  ON public.parents
  FOR SELECT
  USING (
    auth.uid() = owner_id
    OR EXISTS (
      SELECT 1
      FROM public.invitations i
      WHERE i.parent_id = parents.id
        AND i.used_by = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_settings us
      WHERE us.profile_id = auth.uid()
        AND (
          us.parent_invite_id = parents.numeric_id
          OR us.parent_self_profile->>'numericId' = parents.numeric_id
        )
    )
  );

CREATE POLICY "Linked elderly can view parent alarms"
  ON public.parent_alarms
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.parents p
      WHERE p.id = parent_alarms.parent_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.invitations i ON i.parent_id = p.id
      WHERE p.id = parent_alarms.parent_id
        AND i.used_by = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.user_settings us ON us.profile_id = auth.uid()
      WHERE p.id = parent_alarms.parent_id
        AND (
          us.parent_invite_id = p.numeric_id
          OR us.parent_self_profile->>'numericId' = p.numeric_id
        )
    )
  );

CREATE POLICY "Linked elderly can view daily check-ins"
  ON public.daily_check_ins
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.parents p
      WHERE p.id = daily_check_ins.parent_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.invitations i ON i.parent_id = p.id
      WHERE p.id = daily_check_ins.parent_id
        AND i.used_by = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.user_settings us ON us.profile_id = auth.uid()
      WHERE p.id = daily_check_ins.parent_id
        AND (
          us.parent_invite_id = p.numeric_id
          OR us.parent_self_profile->>'numericId' = p.numeric_id
        )
    )
  );

CREATE POLICY "Linked elderly can upsert daily check-ins"
  ON public.daily_check_ins
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.user_settings us ON us.profile_id = auth.uid()
      WHERE p.id = daily_check_ins.parent_id
        AND (
          us.parent_invite_id = p.numeric_id
          OR us.parent_self_profile->>'numericId' = p.numeric_id
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.invitations i ON i.parent_id = p.id
      WHERE p.id = daily_check_ins.parent_id
        AND i.used_by = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.user_settings us ON us.profile_id = auth.uid()
      WHERE p.id = daily_check_ins.parent_id
        AND (
          us.parent_invite_id = p.numeric_id
          OR us.parent_self_profile->>'numericId' = p.numeric_id
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.parents p
      JOIN public.invitations i ON i.parent_id = p.id
      WHERE p.id = daily_check_ins.parent_id
        AND i.used_by = auth.uid()
    )
  );
