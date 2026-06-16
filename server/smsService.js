import twilio from 'twilio';
import { getSupabaseAdmin } from './supabaseAdmin.js';

let twilioClient = null;

function getTwilioClient() {
  if (twilioClient) return twilioClient;

  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) return null;

  twilioClient = twilio(sid, token);
  return twilioClient;
}

export async function sendSmsToProfile(profileId, { title, message, level, parentId }) {
  const client = getTwilioClient();
  const from = process.env.TWILIO_FROM_NUMBER;
  if (!client || !from) return;

  const admin = getSupabaseAdmin();

  const { data: profile } = await admin
    .from('profiles')
    .select('phone')
    .eq('id', profileId)
    .maybeSingle();

  if (!profile?.phone) return;

  let shouldSend = level >= 3;
  if (parentId) {
    const { data: prefs } = await admin
      .from('notification_prefs')
      .select('level2_sms, level3_sms')
      .eq('profile_id', profileId)
      .eq('parent_id', parentId)
      .maybeSingle();

    if (prefs) {
      shouldSend = level >= 3 ? prefs.level3_sms : level >= 2 ? prefs.level2_sms : false;
    }
  }

  if (!shouldSend) return;

  try {
    await client.messages.create({
      from,
      to: profile.phone,
      body: `${title}: ${message}`,
    });
  } catch (error) {
    console.warn(`[sms] Failed for ${profileId}:`, error);
  }
}
