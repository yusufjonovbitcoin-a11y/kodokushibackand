import { createClient } from '@supabase/supabase-js';
import ws from 'ws';

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

let adminClient = null;

export function isSupabaseAdminConfigured() {
  return Boolean(supabaseUrl && serviceRoleKey);
}

function looksLikeAnonKey(key) {
  if (!key || key.startsWith('sb_secret_')) return false;
  try {
    const payload = key.split('.')[1];
    if (!payload) return false;
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return decoded?.role === 'anon';
  } catch {
    return false;
  }
}

export async function verifySupabaseServiceRole() {
  if (!isSupabaseAdminConfigured()) {
    return { ok: false, reason: 'MISSING_ENV' };
  }

  if (looksLikeAnonKey(serviceRoleKey)) {
    return { ok: false, reason: 'ANON_KEY_USED' };
  }

  const admin = getSupabaseAdmin();
  const { error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1 });
  if (error) {
    if (error.message === 'User not allowed') {
      return { ok: false, reason: 'ANON_KEY_USED' };
    }
    return { ok: false, reason: 'AUTH_ADMIN_FAILED', detail: error.message };
  }

  return { ok: true };
}

export function getSupabaseAdmin() {
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
  }

  if (!adminClient) {
    adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      // Node.js 20 on Render has no native WebSocket; Supabase Realtime requires `ws`.
      realtime: { transport: ws },
    });
  }

  return adminClient;
}
