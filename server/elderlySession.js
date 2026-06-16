import crypto from 'crypto';
import { getSupabaseAdmin, isSupabaseAdminConfigured } from './supabaseAdmin.js';

export function isElderlySessionConfigured() {
  return isSupabaseAdminConfigured();
}

export async function createElderlyDeviceSession() {
  const admin = getSupabaseAdmin();
  const deviceId = crypto.randomUUID();
  const email = `elderly+${deviceId}@mimamori.device`;
  const password = crypto.randomBytes(24).toString('base64url');

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      elderly_device: true,
      device_id: deviceId,
    },
    app_metadata: {
      provider: 'elderly_device',
    },
  });

  if (error) throw error;
  if (!data.user) throw new Error('DEVICE_USER_CREATE_FAILED');

  return {
    userId: data.user.id,
    email,
    password,
  };
}
