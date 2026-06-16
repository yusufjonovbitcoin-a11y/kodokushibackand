# Kodokushi Backend

Socket.IO, REST API, medicine scheduler, and push/SMS notifications for the Mimamori family care app.

Frontend: `../Kodokushi1`

## Setup

```bash
cd kodokushibackand
npm install
cp .env.example .env
# Fill in .env (see below)
npm run dev
```

Server: `http://localhost:3001`

## Environment

Copy `.env.example` and configure:

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | No | Default `3001` |
| `CLIENT_ORIGIN` | Yes | Comma-separated frontend origins for CORS |
| `SUPABASE_URL` | Yes | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Service role key (backend only) |
| `OPENAI_API_KEY` | No | Prescription image parsing |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | No | FCM push (JSON string) |
| `TWILIO_*` | No | SMS alerts |
| `MEDICINE_REMINDER_TZ` | No | IANA timezone for medicine reminders (default `Asia/Tokyo`) |

**Never** put `SUPABASE_SERVICE_ROLE_KEY` in the frontend.

## API

Protected routes require `Authorization: Bearer <supabase_access_token>`.

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Health check |
| `/api/prescription/parse` | POST | JWT | AI prescription parsing |
| `/api/elderly/device-session` | POST | No | Elderly device login (`{ inviteCode }`, rate-limited) |

Socket.IO: connect with `auth: { token: <supabase_access_token> }`. Parent-scoped events require membership or linked elderly access.

## Supabase migrations

Run in order in the Supabase SQL Editor (`supabase/migrations/`):

1. `001_initial_schema.sql` through `018_elderly_family_contacts.sql`
2. `019_upsert_linked_daily_check_in.sql` — elderly check-in RPC
3. `020_update_linked_parent_alarms.sql` — elderly alarm update RPC

**Manual apply scripts** (for existing DBs that skipped migrations):

- `apply_upsert_linked_daily_check_in.sql`
- `apply_update_linked_parent_alarms.sql`
- `apply_fix_elderly_alarms.sql` (legacy DBs only)

## Medicine scheduler

Runs every 30 seconds when `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set. Uses `MEDICINE_REMINDER_TZ` for date/time matching. Creates in-app notifications and dispatches push/SMS via `notificationHub.js` when configured.

## Docker deploy

```bash
docker build -t kodokushi-backend .
docker run -p 3001:3001 --env-file .env kodokushi-backend
```

The image does not include `.env`; pass environment variables at runtime via `--env-file` or platform secrets.

Health check: `GET /health`

## Render deploy (internet APK uchun)

Mobil APK internet orqali ishlashi uchun backend **public HTTPS** da bo‘lishi kerak.

1. [render.com](https://render.com) ga kiring, **New → Blueprint** yoki **Web Service → Docker**
2. `kodokushibackand` repozitoriyasini ulang (yoki `render.yaml` bilan deploy qiling)
3. Environment variables qo‘ying (`.env` dagi qiymatlar):
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - ixtiyoriy: `OPENAI_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `TWILIO_*`
4. Deploy tugagach URL oling, masalan: `https://kodokushi-backend.onrender.com`
5. `KodokushiMobile/.env` da `EXPO_PUBLIC_SOCKET_URL` ni shu URL ga qo‘ying
6. APK ni qayta build qiling: `eas build --profile preview --platform android`

**Muhim:** `localhost` yoki `192.168.x.x` telefonda ishlamaydi — faqat public HTTPS.


## Frontend `.env`

In `Kodokushi1/.env` (see `Kodokushi1/.env.example`):

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_SOCKET_URL=http://localhost:3001
VITE_TURN_URL=...          # optional WebRTC
VITE_FIREBASE_*=...         # optional push
```

## Auth (Supabase)

### Email OTP

Dashboard → **Authentication** → **Providers** → **Email**: enable Email + OTP.

**Email Templates** → **Magic Link** must use `{{ .Token }}` (not only `{{ .ConfirmationURL }}`).

### Custom SMTP (Resend)

- Host: `smtp.resend.com`, Port: `587`, User: `resend`, Password: Resend API key
- Sender must be a verified domain

### Google OAuth

Google Cloud → OAuth client → redirect URI:

```
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

Supabase → **Authentication** → **Providers** → **Google** → enable and paste client credentials.

Redirect URLs for local dev:

- `http://localhost:3000/auth/callback`
- `http://localhost:3002/auth/callback`
- `mimamori://auth/callback`
