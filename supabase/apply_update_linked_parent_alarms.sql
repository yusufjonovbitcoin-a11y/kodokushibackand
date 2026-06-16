-- Allow linked elderly users to update parent check-in alarm times.
-- Run in Supabase SQL Editor after apply_fix_elderly_alarms.sql.

CREATE OR REPLACE FUNCTION public.update_linked_parent_alarms(
  p_numeric_id TEXT,
  p_alarms JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_owner_id UUID;
  v_slot TEXT;
  v_enabled BOOLEAN;
  v_time TEXT;
  v_morning_time TEXT;
  v_afternoon_time TEXT;
BEGIN
  IF p_numeric_id IS NULL OR trim(p_numeric_id) = '' THEN
    RAISE EXCEPTION 'INVALID_NUMERIC_ID';
  END IF;

  IF p_alarms IS NULL OR jsonb_typeof(p_alarms) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_ALARMS';
  END IF;

  SELECT p.id, p.owner_id
  INTO v_parent_id, v_owner_id
  FROM public.parents p
  WHERE p.numeric_id = trim(p_numeric_id)
  LIMIT 1;

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION 'PARENT_NOT_FOUND';
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
    RAISE EXCEPTION 'NOT_LINKED';
  END IF;

  FOREACH v_slot IN ARRAY ARRAY['morning', 'afternoon', 'evening']
  LOOP
    v_enabled := COALESCE(
      (p_alarms -> v_slot ->> 'enabled')::BOOLEAN,
      CASE WHEN v_slot = 'evening' THEN FALSE ELSE TRUE END
    );
    v_time := COALESCE(
      NULLIF(trim(p_alarms -> v_slot ->> 'time'), ''),
      CASE v_slot
        WHEN 'morning' THEN '08:00'
        WHEN 'afternoon' THEN '13:00'
        ELSE '19:00'
      END
    );

    INSERT INTO public.parent_alarms (parent_id, slot, enabled, time)
    VALUES (v_parent_id, v_slot, v_enabled, v_time)
    ON CONFLICT (parent_id, slot) DO UPDATE
      SET enabled = EXCLUDED.enabled,
          time = EXCLUDED.time;
  END LOOP;

  v_morning_time := COALESCE(
    NULLIF(trim(p_alarms -> 'morning' ->> 'time'), ''),
    '08:00'
  );
  v_afternoon_time := COALESCE(
    NULLIF(trim(p_alarms -> 'afternoon' ->> 'time'), ''),
    '13:00'
  );

  IF v_owner_id IS NOT NULL THEN
    INSERT INTO public.notification_prefs (
      profile_id,
      parent_id,
      level1_alarm_time,
      level2_alarm_time
    )
    VALUES (
      v_owner_id,
      v_parent_id,
      v_morning_time,
      v_afternoon_time
    )
    ON CONFLICT (profile_id, parent_id) DO UPDATE
      SET level1_alarm_time = EXCLUDED.level1_alarm_time,
          level2_alarm_time = EXCLUDED.level2_alarm_time;
  END IF;

  RETURN jsonb_build_object(
    'morning', jsonb_build_object(
      'enabled', COALESCE((p_alarms -> 'morning' ->> 'enabled')::BOOLEAN, TRUE),
      'time', v_morning_time
    ),
    'afternoon', jsonb_build_object(
      'enabled', COALESCE((p_alarms -> 'afternoon' ->> 'enabled')::BOOLEAN, TRUE),
      'time', v_afternoon_time
    ),
    'evening', COALESCE(
      p_alarms -> 'evening',
      jsonb_build_object('enabled', FALSE, 'time', '19:00')
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_linked_parent_alarms(TEXT, JSONB) TO authenticated;
