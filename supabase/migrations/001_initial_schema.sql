-- Mimamori Family — initial Supabase schema
-- Run in Supabase SQL Editor or via: supabase db push

-- ── Profiles (linked to auth.users) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name          TEXT,
  phone         TEXT,
  email         TEXT,
  relationship  TEXT,
  relationship_key TEXT CHECK (relationship_key IN ('son', 'daughter', 'relative', 'caretaker')),
  user_role     TEXT CHECK (user_role IN ('family', 'parent')),
  parent_app_mode TEXT NOT NULL DEFAULT 'family' CHECK (parent_app_mode IN ('elderly', 'family')),
  onboarding_complete BOOLEAN NOT NULL DEFAULT FALSE,
  language      TEXT NOT NULL DEFAULT 'en',
  theme         TEXT NOT NULL DEFAULT 'light' CHECK (theme IN ('light', 'dark')),
  auth_method   TEXT CHECK (auth_method IN ('email', 'google')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Parents (monitored elderly) ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.parents (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id            UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  numeric_id          TEXT NOT NULL UNIQUE,
  name                TEXT NOT NULL,
  age                 INTEGER,
  city                TEXT,
  phone               TEXT,
  address             TEXT,
  photo_url           TEXT,
  status              TEXT NOT NULL DEFAULT 'all-good'
                      CHECK (status IN ('all-good', 'caution', 'warning', 'danger')),
  last_check_in       TIMESTAMPTZ,
  missed_alarms_today INTEGER NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.parent_alarms (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  slot      TEXT NOT NULL CHECK (slot IN ('morning', 'afternoon', 'evening')),
  enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  time      TEXT NOT NULL DEFAULT '08:00',
  UNIQUE (parent_id, slot)
);

CREATE TABLE IF NOT EXISTS public.daily_check_ins (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id       UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  confirmed_slots TEXT[] NOT NULL DEFAULT '{}',
  missed_slots    TEXT[] NOT NULL DEFAULT '{}',
  confirmed_at    JSONB NOT NULL DEFAULT '{}',
  UNIQUE (parent_id, date)
);

-- ── Family members & invitations ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.family_members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id     UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  profile_id    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  phone         TEXT,
  relationship  TEXT,
  role          TEXT NOT NULL DEFAULT 'secondary' CHECK (role IN ('primary', 'secondary')),
  alert_level1  BOOLEAN NOT NULL DEFAULT TRUE,
  alert_level2  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.invitations (
  id         TEXT PRIMARY KEY,
  parent_id  UUID REFERENCES public.parents(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ,
  used_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Notifications & alerts ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_prefs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id          UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id           UUID REFERENCES public.parents(id) ON DELETE CASCADE,
  level1_push         BOOLEAN NOT NULL DEFAULT TRUE,
  level2_push         BOOLEAN NOT NULL DEFAULT TRUE,
  level2_sms          BOOLEAN NOT NULL DEFAULT FALSE,
  level3_push         BOOLEAN NOT NULL DEFAULT TRUE,
  level3_sms          BOOLEAN NOT NULL DEFAULT TRUE,
  quiet_hours_start   TEXT NOT NULL DEFAULT '22:00',
  quiet_hours_end     TEXT NOT NULL DEFAULT '07:00',
  UNIQUE (profile_id, parent_id)
);

CREATE TABLE IF NOT EXISTS public.notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id  UUID REFERENCES public.parents(id) ON DELETE SET NULL,
  title      TEXT NOT NULL,
  message    TEXT NOT NULL,
  level      INTEGER NOT NULL DEFAULT 1,
  read       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.active_alerts (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                 UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id                UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  parent_name              TEXT NOT NULL,
  time_since_last_check_in TEXT NOT NULL DEFAULT '',
  triggered_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved                 BOOLEAN NOT NULL DEFAULT FALSE,
  resolved_at              TIMESTAMPTZ,
  action_taken             TEXT
);

CREATE TABLE IF NOT EXISTS public.missed_alarm_logs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id    UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  date         DATE NOT NULL,
  time         TEXT NOT NULL,
  alarm_label  TEXT NOT NULL,
  action_taken TEXT
);

-- ── Emergency plans & contacts ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.emergency_plans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id           UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE UNIQUE,
  home_address        TEXT,
  home_lat            DOUBLE PRECISION,
  home_lng            DOUBLE PRECISION,
  contacts            JSONB NOT NULL DEFAULT '[]',
  priority_visitors   JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS public.elderly_contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  phone      TEXT,
  relation   TEXT
);

CREATE TABLE IF NOT EXISTS public.parent_family_contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  phone      TEXT
);

-- ── Children (parent app mode) ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.children (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  phone        TEXT,
  relationship TEXT,
  age          INTEGER,
  city         TEXT,
  status       TEXT NOT NULL DEFAULT 'all-good'
               CHECK (status IN ('all-good', 'caution', 'warning', 'danger')),
  last_seen    TIMESTAMPTZ,
  reminders    JSONB NOT NULL DEFAULT '[]'
);

-- ── User settings (ringtones, app state) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_settings (
  profile_id                          UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_ringtone                       TEXT NOT NULL DEFAULT 'default',
  device_ringtone_name                TEXT NOT NULL DEFAULT '',
  parent_user_ringtone                TEXT NOT NULL DEFAULT 'default',
  parent_user_device_ringtone_name    TEXT NOT NULL DEFAULT '',
  parent_ringtones                    JSONB NOT NULL DEFAULT '{}',
  parent_device_ringtones             JSONB NOT NULL DEFAULT '{}',
  child_ringtones                     JSONB NOT NULL DEFAULT '{}',
  child_device_ringtones              JSONB NOT NULL DEFAULT '{}',
  parent_self_profile                 JSONB,
  parent_invite_id                    TEXT,
  setup_mode                          TEXT CHECK (setup_mode IN ('send-invitation', 'accept-invitation')),
  parent_user_notification_prefs      JSONB NOT NULL DEFAULT '{}',
  child_notification_prefs            JSONB NOT NULL DEFAULT '{}'
);

-- ── updated_at trigger ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER parents_updated_at
  BEFORE UPDATE ON public.parents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── Auto-create profile on email/Google signup ───────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, auth_method)
  VALUES (
    NEW.id,
    NEW.email,
    CASE
      WHEN NEW.raw_app_meta_data->>'provider' = 'google' THEN 'google'
      ELSE 'email'
    END
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── Row Level Security ─────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_alarms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.active_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missed_alarm_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.elderly_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_family_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- parents
CREATE POLICY "Owners manage parents" ON public.parents FOR ALL USING (auth.uid() = owner_id);

-- parent_alarms (via parent ownership)
CREATE POLICY "Owners manage parent alarms" ON public.parent_alarms FOR ALL
  USING (EXISTS (SELECT 1 FROM public.parents p WHERE p.id = parent_id AND p.owner_id = auth.uid()));

-- daily_check_ins
CREATE POLICY "Owners manage check-ins" ON public.daily_check_ins FOR ALL
  USING (EXISTS (SELECT 1 FROM public.parents p WHERE p.id = parent_id AND p.owner_id = auth.uid()));

-- family_members
CREATE POLICY "Owners manage family members" ON public.family_members FOR ALL
  USING (EXISTS (SELECT 1 FROM public.parents p WHERE p.id = parent_id AND p.owner_id = auth.uid()));

-- invitations
CREATE POLICY "Users manage own invitations" ON public.invitations FOR ALL USING (auth.uid() = created_by);
CREATE POLICY "Anyone can read invitation by id" ON public.invitations FOR SELECT USING (TRUE);

-- notification_prefs
CREATE POLICY "Users manage own notification prefs" ON public.notification_prefs FOR ALL USING (auth.uid() = profile_id);

-- notifications
CREATE POLICY "Users manage own notifications" ON public.notifications FOR ALL USING (auth.uid() = profile_id);

-- active_alerts
CREATE POLICY "Owners manage active alerts" ON public.active_alerts FOR ALL USING (auth.uid() = owner_id);

-- missed_alarm_logs
CREATE POLICY "Owners manage missed alarm logs" ON public.missed_alarm_logs FOR ALL
  USING (EXISTS (SELECT 1 FROM public.parents p WHERE p.id = parent_id AND p.owner_id = auth.uid()));

-- emergency_plans
CREATE POLICY "Owners manage emergency plans" ON public.emergency_plans FOR ALL
  USING (EXISTS (SELECT 1 FROM public.parents p WHERE p.id = parent_id AND p.owner_id = auth.uid()));

-- contacts
CREATE POLICY "Users manage elderly contacts" ON public.elderly_contacts FOR ALL USING (auth.uid() = profile_id);
CREATE POLICY "Users manage parent family contacts" ON public.parent_family_contacts FOR ALL USING (auth.uid() = profile_id);

-- children
CREATE POLICY "Owners manage children" ON public.children FOR ALL USING (auth.uid() = owner_id);

-- user_settings
CREATE POLICY "Users manage own settings" ON public.user_settings FOR ALL USING (auth.uid() = profile_id);

-- Realtime (optional — enable in Supabase dashboard for live updates)
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.parents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.active_alerts;
