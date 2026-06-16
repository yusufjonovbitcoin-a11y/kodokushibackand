import { getSupabaseAdmin, isSupabaseAdminConfigured } from './supabaseAdmin.js';
import { dispatchNotification } from './notificationHub.js';

const CHECK_INTERVAL_MS = 30_000;
const REMINDER_WINDOW_MS = 60_000;
const SCHEDULER_TZ = process.env.MEDICINE_REMINDER_TZ || 'Asia/Tokyo';

function getTodayKey(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: SCHEDULER_TZ }).format(now);
}

function getCurrentMinutes(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: SCHEDULER_TZ,
    hour: 'numeric',
    minute: 'numeric',
    hour12: false,
  }).formatToParts(now);
  const hour = Number(parts.find((p) => p.type === 'hour')?.value ?? 0);
  const minute = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
  return hour * 60 + minute;
}

function isTimeDue(scheduledTime, now = new Date()) {
  const [hours, minutes] = scheduledTime.split(':').map(Number);
  const targetMinutes = hours * 60 + minutes;
  const nowMinutes = getCurrentMinutes(now);
  return Math.abs(nowMinutes - targetMinutes) * 60_000 <= REMINDER_WINDOW_MS;
}

function buildReminderMessage(item) {
  const dosePart = item.dose ? ` (${item.dose})` : '';
  const instructionPart = item.instructions ? ` — ${item.instructions}` : '';
  return `💊 Medicine reminder: Take ${item.name}${dosePart}${instructionPart}`;
}

async function findElderlyProfileId(supabase, parentId) {
  const { data: parent } = await supabase
    .from('parents')
    .select('numeric_id')
    .eq('id', parentId)
    .maybeSingle();

  if (!parent?.numeric_id) return null;

  const { data: settings } = await supabase
    .from('user_settings')
    .select('profile_id, parent_self_profile')
    .not('parent_self_profile', 'is', null);

  const match = (settings ?? []).find((row) => {
    const profile = row.parent_self_profile;
    return profile?.numericId === parent.numeric_id;
  });

  return match?.profile_id ?? null;
}

async function findNotifyProfileIds(supabase, parentId) {
  const { data: parent } = await supabase
    .from('parents')
    .select('owner_id')
    .eq('id', parentId)
    .maybeSingle();

  const { data: members } = await supabase
    .from('family_members')
    .select('profile_id')
    .eq('parent_id', parentId)
    .not('profile_id', 'is', null);

  const elderlyProfileId = await findElderlyProfileId(supabase, parentId);

  return [...new Set([
    elderlyProfileId,
    parent?.owner_id,
    ...(members ?? []).map((row) => row.profile_id),
  ].filter(Boolean))];
}

async function hasReminderBeenSent(supabase, medicineItemId, scheduledDate, scheduledTime) {
  const { data } = await supabase
    .from('medicine_reminder_logs')
    .select('id')
    .eq('medicine_item_id', medicineItemId)
    .eq('scheduled_date', scheduledDate)
    .eq('scheduled_time', scheduledTime)
    .maybeSingle();

  return Boolean(data);
}

async function recordReminderLog(supabase, item, today, time) {
  const { error } = await supabase.from('medicine_reminder_logs').insert({
    medicine_item_id: item.id,
    parent_id: item.parent_id,
    scheduled_date: today,
    scheduled_time: time,
  });

  if (error) {
    if (error.code === '23505') return false;
    throw error;
  }
  return true;
}

async function sendReminder(supabase, item, today, time) {
  const logged = await recordReminderLog(supabase, item, today, time);
  if (!logged) return;

  const message = buildReminderMessage(item);
  const title = `Medicine: ${item.name}`;

  await supabase.from('chat_messages').insert({
    parent_id: item.parent_id,
    sender_id: item.created_by,
    content: message,
    message_type: 'system',
  });

  const profileIds = await findNotifyProfileIds(supabase, item.parent_id);
  await Promise.all(
    profileIds.map(async (profileId) => {
      await supabase.from('notifications').insert({
        profile_id: profileId,
        parent_id: item.parent_id,
        title,
        message,
        level: 1,
      });
      await dispatchNotification({
        profileId,
        title,
        message,
        level: 1,
        parentId: item.parent_id,
      });
    }),
  );
}

let running = false;

async function tick() {
  if (running || !isSupabaseAdminConfigured()) return;
  running = true;

  try {
    const supabase = getSupabaseAdmin();
    const { data: items, error } = await supabase
      .from('medicine_items')
      .select('*')
      .eq('active', true);

    if (error) throw error;
    if (!items?.length) return;

    const now = new Date();
    const today = getTodayKey(now);

    for (const item of items) {
      for (const time of item.times ?? []) {
        if (!isTimeDue(time, now)) continue;

        const alreadySent = await hasReminderBeenSent(supabase, item.id, today, time);
        if (alreadySent) continue;

        await sendReminder(supabase, item, today, time);
        console.log(`[medicine-reminder] sent ${item.name} at ${time} for parent ${item.parent_id}`);
      }
    }
  } catch (error) {
    console.error('[medicine-reminder]', error);
  } finally {
    running = false;
  }
}

export function startMedicineReminderScheduler() {
  if (!isSupabaseAdminConfigured()) {
    console.warn('[medicine-reminder] disabled — SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing');
    return;
  }

  tick();
  setInterval(tick, CHECK_INTERVAL_MS);
  console.log(`[medicine-reminder] scheduler started (tz=${SCHEDULER_TZ})`);
}
