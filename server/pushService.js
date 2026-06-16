import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { getSupabaseAdmin } from './supabaseAdmin.js';

let messaging = null;

function getMessagingClient() {
  if (messaging) return messaging;

  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!json) return null;

  try {
    const serviceAccount = JSON.parse(json);
    if (getApps().length === 0) {
      initializeApp({ credential: cert(serviceAccount) });
    }
    messaging = getMessaging();
    return messaging;
  } catch (error) {
    console.warn('[push] Firebase init failed:', error);
    return null;
  }
}

export async function sendPushToProfile(profileId, { title, message, level, parentId }) {
  const fcm = getMessagingClient();
  if (!fcm) return;

  const admin = getSupabaseAdmin();
  const { data: subs } = await admin
    .from('push_subscriptions')
    .select('endpoint')
    .eq('profile_id', profileId);

  if (!subs?.length) return;

  for (const sub of subs) {
    if (!sub.endpoint) continue;
    try {
      await fcm.send({
        token: sub.endpoint,
        notification: { title, body: message },
        data: {
          level: String(level ?? 1),
          parentId: parentId ?? '',
        },
      });
    } catch (error) {
      console.warn(`[push] Failed for ${profileId}:`, error);
    }
  }
}
