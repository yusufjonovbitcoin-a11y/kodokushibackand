-- Elderly device can log missed check-ins and notify family owner (bypasses RLS)

CREATE OR REPLACE FUNCTION public.log_linked_missed_check_in(
  p_slot_label TEXT,
  p_date DATE,
  p_alarm_time TEXT,
  p_create_danger_alert BOOLEAN DEFAULT FALSE
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
BEGIN
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

  SELECT p.id, p.owner_id, p.name
  INTO v_parent_id, v_owner_id, v_parent_name
  FROM public.parents p
  WHERE p.numeric_id = v_numeric_id;

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION 'PARENT_NOT_FOUND';
  END IF;

  INSERT INTO public.missed_alarm_logs (parent_id, date, time, alarm_label)
  VALUES (v_parent_id, p_date, p_alarm_time, p_slot_label);

  INSERT INTO public.notifications (profile_id, parent_id, title, message, level)
  VALUES (
    v_owner_id,
    v_parent_id,
    'Missed Check-in',
    p_slot_label || ' check-in was missed',
    2
  );

  UPDATE public.parents
  SET status = 'warning'
  WHERE id = v_parent_id AND status <> 'danger';

  IF p_create_danger_alert THEN
    INSERT INTO public.active_alerts (
      owner_id,
      parent_id,
      parent_name,
      time_since_last_check_in
    )
    VALUES (
      v_owner_id,
      v_parent_id,
      v_parent_name,
      '2+ hours'
    );
  END IF;

  RETURN v_parent_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_linked_missed_check_in(TEXT, DATE, TEXT, BOOLEAN) TO authenticated;
