-- Chat, care tasks, and web push subscriptions

CREATE OR REPLACE FUNCTION public.can_access_parent(parent_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.parents p
    WHERE p.id = parent_uuid AND p.owner_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.parents p
    JOIN public.user_settings us ON us.profile_id = auth.uid()
    WHERE p.id = parent_uuid
      AND us.parent_self_profile IS NOT NULL
      AND (us.parent_self_profile->>'numericId') = p.numeric_id
  )
  OR EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.parent_id = parent_uuid AND fm.profile_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id    UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  sender_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content      TEXT NOT NULL,
  message_type TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'system')),
  read_by      UUID[] NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS chat_messages_parent_id_created_at_idx
  ON public.chat_messages (parent_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.care_tasks (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id    UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE,
  created_by   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  description  TEXT,
  due_date     DATE,
  completed    BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS care_tasks_parent_id_idx
  ON public.care_tasks (parent_id, completed, due_date);

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  endpoint   TEXT NOT NULL,
  p256dh     TEXT NOT NULL,
  auth       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (profile_id, endpoint)
);

CREATE TRIGGER care_tasks_updated_at
  BEFORE UPDATE ON public.care_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.care_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Chat access for linked users" ON public.chat_messages
  FOR SELECT USING (public.can_access_parent(parent_id));

CREATE POLICY "Chat insert for linked users" ON public.chat_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND public.can_access_parent(parent_id)
  );

CREATE POLICY "Chat update read status" ON public.chat_messages
  FOR UPDATE USING (public.can_access_parent(parent_id));

CREATE POLICY "Tasks access for linked users" ON public.care_tasks
  FOR SELECT USING (public.can_access_parent(parent_id));

CREATE POLICY "Tasks insert for linked users" ON public.care_tasks
  FOR INSERT WITH CHECK (
    created_by = auth.uid() AND public.can_access_parent(parent_id)
  );

CREATE POLICY "Tasks update for linked users" ON public.care_tasks
  FOR UPDATE USING (public.can_access_parent(parent_id));

CREATE POLICY "Tasks delete for owner or creator" ON public.care_tasks
  FOR DELETE USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.parents p
      WHERE p.id = parent_id AND p.owner_id = auth.uid()
    )
  );

CREATE POLICY "Users manage own push subscriptions" ON public.push_subscriptions
  FOR ALL USING (auth.uid() = profile_id);

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.care_tasks;
