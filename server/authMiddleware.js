import { getSupabaseAdmin, isSupabaseAdminConfigured } from './supabaseAdmin.js';

async function verifyAccessToken(token) {
  if (!token || typeof token !== 'string') {
    return null;
  }

  if (!isSupabaseAdminConfigured()) {
    throw new Error('SUPABASE_ADMIN_NOT_CONFIGURED');
  }

  const admin = getSupabaseAdmin();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user?.id) {
    return null;
  }

  return data.user;
}

function extractBearerToken(req) {
  const header = req.headers.authorization;
  if (!header || typeof header !== 'string') return null;
  const [scheme, token] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) return null;
  return token;
}

export async function requireAuth(req, res, next) {
  try {
    const token = extractBearerToken(req);
    if (!token) {
      res.status(401).json({ error: 'UNAUTHORIZED' });
      return;
    }

    const user = await verifyAccessToken(token);
    if (!user) {
      res.status(401).json({ error: 'INVALID_TOKEN' });
      return;
    }

    req.authUser = user;
    req.userId = user.id;
    next();
  } catch (error) {
    const message = error instanceof Error ? error.message : 'AUTH_FAILED';
    res.status(503).json({ error: message });
  }
}

export async function verifySocketToken(socket) {
  const token = socket.handshake.auth?.token;
  const user = await verifyAccessToken(token);
  if (!user) {
    throw new Error('Unauthorized');
  }
  return user;
}
