ALTER TABLE public.notification_prefs
  ADD COLUMN IF NOT EXISTS level2_alarm_time TEXT NOT NULL DEFAULT '13:00';
