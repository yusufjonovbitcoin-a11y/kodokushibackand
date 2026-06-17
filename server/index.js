import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { parsePrescriptionWithAI } from './prescriptionAi.js';
import { startMedicineReminderScheduler } from './medicineScheduler.js';
import { getSupabaseAdmin, isSupabaseAdminConfigured, verifySupabaseServiceRole, getSupabaseEnvDiagnostics } from './supabaseAdmin.js';
import {
  createElderlyDeviceSession,
  isElderlySessionConfigured,
} from './elderlySession.js';
import { requireAuth, verifySocketToken } from './authMiddleware.js';
import { guardParentAccess, guardUsersShareAccess } from './parentAccess.js';

const PORT = Number(process.env.PORT) || 3001;

const DEFAULT_ORIGINS = [
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:3002',
  'http://127.0.0.1:3002',
  'http://192.168.1.2:3000',
];

const CLIENT_ORIGINS = process.env.CLIENT_ORIGIN
  ? process.env.CLIENT_ORIGIN.split(',').map((origin) => origin.trim()).filter(Boolean)
  : DEFAULT_ORIGINS;

function isAllowedOrigin(origin) {
  // React Native, Socket.IO mobile clients, and health checks send no Origin header.
  if (!origin) return true;
  return CLIENT_ORIGINS.includes(origin);
}

const corsOptions = {
  origin(origin, callback) {
    if (isAllowedOrigin(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
};

const deviceSessionLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'RATE_LIMITED' },
  // Limit per invite code, not shared Render/proxy IP (avoids blocking all users together).
  keyGenerator: (req) => {
    const inviteCode = typeof req.body?.inviteCode === 'string' ? req.body.inviteCode.trim() : '';
    return inviteCode || req.ip || 'unknown';
  },
  // Failed setup attempts (wrong keys, etc.) should not burn the budget for a successful login.
  skipSuccessfulRequests: true,
});

const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'RATE_LIMITED' },
});

const app = express();
app.set('trust proxy', 1);
app.use(cors(corsOptions));
app.use(express.json({ limit: '10mb' }));

app.get('/health', async (_req, res) => {
  const serviceRole = await verifySupabaseServiceRole();
  const envDiag = getSupabaseEnvDiagnostics();
  res.json({
    ok: serviceRole.ok,
    service: 'kodokushi-backend',
    port: PORT,
    origins: CLIENT_ORIGINS,
    supabaseAdmin: isSupabaseAdminConfigured(),
    supabaseProjectRef: envDiag.supabaseProjectRef,
    serviceRoleKeyType: envDiag.serviceRoleKeyType,
    serviceRoleValid: serviceRole.ok,
    serviceRoleIssue: serviceRole.ok ? null : serviceRole.reason,
    elderlySession: isSupabaseAdminConfigured() && serviceRole.ok,
    openai: Boolean(process.env.OPENAI_API_KEY),
  });
});

app.post('/api/elderly/device-session', deviceSessionLimiter, async (req, res) => {
  try {
    if (!isElderlySessionConfigured()) {
      res.status(503).json({ error: 'SUPABASE_ADMIN_NOT_CONFIGURED' });
      return;
    }

    const inviteCode = typeof req.body?.inviteCode === 'string' ? req.body.inviteCode.trim() : '';
    if (!inviteCode) {
      res.status(400).json({ error: 'INVITE_CODE_REQUIRED' });
      return;
    }

    const admin = getSupabaseAdmin();
    const { data: joinInfo, error: verifyError } = await admin.rpc('verify_join_code', {
      invite_code: inviteCode,
    });

    if (verifyError || !joinInfo?.length) {
      res.status(400).json({ error: 'INVALID_INVITE_CODE' });
      return;
    }

    const verified = joinInfo[0];
    const numericId = verified.numeric_id;

    const session = await createElderlyDeviceSession();

    await admin.from('user_settings').upsert({
      profile_id: session.userId,
      parent_invite_id: numericId,
      parent_self_profile: {
        name: '',
        numericId,
        phone: '',
      },
      setup_mode: null,
    });

    res.json(session);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'DEVICE_SESSION_FAILED';
    if (message === 'User not allowed') {
      res.status(503).json({
        error: 'WRONG_SERVICE_ROLE_KEY',
        hint: 'Render SUPABASE_SERVICE_ROLE_KEY must be Supabase service_role secret (sb_secret_...), not anon key.',
      });
      return;
    }
    res.status(500).json({ error: message });
  }
});

app.post('/api/prescription/parse', apiLimiter, requireAuth, async (req, res) => {
  try {
    const { text, imageDataUrl } = req.body ?? {};
    if (!text?.trim() && !imageDataUrl) {
      res.status(400).json({ error: 'text or imageDataUrl is required' });
      return;
    }

    const medicines = await parsePrescriptionWithAI({ text, imageDataUrl });
    res.json({ medicines });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'PARSE_FAILED';
    const status = code === 'AI_NOT_CONFIGURED' ? 503 : 500;
    res.status(status).json({ error: code });
  }
});

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    ...corsOptions,
    methods: ['GET', 'POST'],
  },
});

io.use(async (socket, next) => {
  try {
    const user = await verifySocketToken(socket);
    socket.data.userId = user.id;
    next();
  } catch {
    next(new Error('Unauthorized'));
  }
});

io.on('connection', (socket) => {
  const userId = socket.data.userId;
  socket.join(`user:${userId}`);
  console.log(`[socket] client joined user:${userId} (${socket.id})`);

  socket.on('realtime:alarms', async (payload) => {
    const parentId = payload?.parentId;
    if (!parentId || typeof parentId !== 'string') return;
    if (!(await guardParentAccess(userId, parentId))) return;
    socket.to(`parent:${parentId}`).emit('realtime:alarms', payload);
  });

  socket.on('webrtc:join-parent', async (payload) => {
    const parentId = payload?.parentId;
    if (!parentId || typeof parentId !== 'string') return;
    if (!(await guardParentAccess(userId, parentId))) return;
    socket.join(`parent:${parentId}`);
    console.log(`[webrtc] user:${userId} joined parent:${parentId}`);
  });

  socket.on('webrtc:leave-parent', async (payload) => {
    const parentId = payload?.parentId;
    if (!parentId || typeof parentId !== 'string') return;
    if (!(await guardParentAccess(userId, parentId))) return;
    socket.leave(`parent:${parentId}`);
  });

  socket.on('webrtc:call', async (payload) => {
    const { targetUserId, parentId, callType, callId, fromName } = payload ?? {};
    if (!targetUserId || !callId || !callType) return;
    if (parentId && !(await guardParentAccess(userId, parentId))) return;
    if (!(await guardUsersShareAccess(userId, targetUserId))) return;

    const incomingPayload = {
      callId,
      callType,
      parentId,
      fromUserId: userId,
      fromName: fromName ?? 'Family',
    };

    socket.to(`user:${targetUserId}`).emit('webrtc:incoming', incomingPayload);

    if (parentId) {
      socket.to(`parent:${parentId}`).emit('webrtc:incoming', incomingPayload);

      try {
        const admin = getSupabaseAdmin();
        const { data } = await admin
          .from('parents')
          .select('owner_id')
          .eq('id', parentId)
          .maybeSingle();
        const ownerId = data?.owner_id;
        if (ownerId && ownerId !== targetUserId && ownerId !== userId) {
          socket.to(`user:${ownerId}`).emit('webrtc:incoming', incomingPayload);
        }
      } catch {
        // parent owner lookup is best-effort
      }
    }
  });

  socket.on('webrtc:accept', async (payload) => {
    const { targetUserId, callId } = payload ?? {};
    if (!targetUserId || !callId) return;
    if (!(await guardUsersShareAccess(userId, targetUserId))) return;
    socket.to(`user:${targetUserId}`).emit('webrtc:accepted', {
      callId,
      fromUserId: userId,
    });
  });

  socket.on('webrtc:signal', async (payload) => {
    const { targetUserId, callId, signal } = payload ?? {};
    if (!targetUserId || !callId || !signal) return;
    if (!(await guardUsersShareAccess(userId, targetUserId))) return;
    socket.to(`user:${targetUserId}`).emit('webrtc:signal', {
      callId,
      fromUserId: userId,
      signal,
    });
  });

  socket.on('webrtc:hangup', async (payload) => {
    const { targetUserId, parentId, callId } = payload ?? {};
    const hangupPayload = { callId, fromUserId: userId };
    if (parentId && !(await guardParentAccess(userId, parentId))) return;
    if (targetUserId) {
      if (!(await guardUsersShareAccess(userId, targetUserId))) return;
      socket.to(`user:${targetUserId}`).emit('webrtc:hangup', hangupPayload);
    }
    if (parentId) {
      socket.to(`parent:${parentId}`).emit('webrtc:hangup', hangupPayload);
    }
  });

  socket.on('realtime:chat', async (payload) => {
    const parentId = payload?.parentId;
    if (!parentId || typeof parentId !== 'string') return;
    if (!(await guardParentAccess(userId, parentId))) return;
    socket.to(`parent:${parentId}`).emit('realtime:chat', payload);
  });

  socket.on('disconnect', (reason) => {
    socket.leave(`user:${userId}`);
    console.log(`[socket] client left user:${userId} (${reason})`);
  });
});

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`Kodokushi backend listening on http://localhost:${PORT}`);
  console.log(`Allowed client origins: ${CLIENT_ORIGINS.join(', ')}`);
  startMedicineReminderScheduler();
});
