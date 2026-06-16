CREATE TABLE IF NOT EXISTS public.medicine_prescriptions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id    UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  created_by   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  image_url    TEXT,
  raw_input    TEXT,
  ai_summary   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.medicine_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id UUID REFERENCES public.medicine_prescriptions(id) ON DELETE SET NULL,
  parent_id       UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  dose            TEXT,
  instructions    TEXT,
  times           TEXT[] NOT NULL DEFAULT '{}',
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.medicine_reminder_logs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  medicine_item_id UUID NOT NULL REFERENCES public.medicine_items(id) ON DELETE CASCADE,
  parent_id        UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  scheduled_date   DATE NOT NULL,
  scheduled_time   TEXT NOT NULL,
  sent_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (medicine_item_id, scheduled_date, scheduled_time)
);

CREATE INDEX IF NOT EXISTS medicine_items_parent_id_idx
  ON public.medicine_items (parent_id) WHERE active = TRUE;

ALTER TABLE public.medicine_prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicine_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicine_reminder_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Prescriptions access" ON public.medicine_prescriptions
  FOR ALL USING (public.can_access_parent(parent_id))
  WITH CHECK (public.can_access_parent(parent_id) AND created_by = auth.uid());

CREATE POLICY "Medicine items access" ON public.medicine_items
  FOR ALL USING (public.can_access_parent(parent_id))
  WITH CHECK (public.can_access_parent(parent_id) AND created_by = auth.uid());

CREATE POLICY "Reminder logs access" ON public.medicine_reminder_logs
  FOR ALL USING (public.can_access_parent(parent_id))
  WITH CHECK (public.can_access_parent(parent_id));

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.medicine_items;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
