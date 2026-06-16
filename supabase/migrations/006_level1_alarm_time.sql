ALTER TABLE public.notification_prefs
  ADD COLUMN IF NOT EXISTS level1_alarm_time TEXT NOT NULL DEFAULT '08:00';
