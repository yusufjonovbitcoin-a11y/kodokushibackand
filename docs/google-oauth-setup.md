# Google OAuth — to'liq sozlash

Loyiha: **osctnkthrlxxxvxkjmzq**

## Sizning aniq Redirect URI

Google Cloud Console ga **faqat shu manzilni** qo'shing:

```
https://osctnkthrlxxxvxkjmzq.supabase.co/auth/v1/callback
```

⚠️ `http://localhost:3000` — Google Cloud ga **QO'SHMANG** (bu Supabase URL Configuration da bo'ladi)

---

## Qadam 1: Google Cloud Console

1. [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials)
2. **+ CREATE CREDENTIALS** → **OAuth client ID**
3. Application type: **Web application**
4. **Authorized redirect URIs** → **ADD URI**:
   ```
   https://osctnkthrlxxxvxkjmzq.supabase.co/auth/v1/callback
   ```
5. **CREATE** → **Client ID** va **Client Secret** ni nusxalang

### OAuth consent screen (majburiy)

1. **APIs & Services** → **OAuth consent screen**
2. User type: **External** (yoki Internal)
3. App name, support email to'ldiring
4. Agar **Testing** rejimida bo'lsa → **Test users** ga o'z Gmail ingizni qo'shing
5. **Save**

---

## Qadam 2: Supabase Dashboard

1. [supabase.com/dashboard](https://supabase.com/dashboard) → loyiha **osctnkthrlxxxvxkjmzq**
2. **Authentication** → **Providers** → **Google**
3. **Enable Sign in with Google** ✅
4. **Client ID** — Google dan (`.apps.googleusercontent.com` bilan tugaydi)
5. **Client Secret** — Google dan (GOCSPX- bilan boshlanadi)
6. **Save**

### URL Configuration

**Authentication** → **URL Configuration** — web va mobil uchun:

- Site URL: `http://localhost:3000` (web dev)
- Redirect URLs (hammasini qo'shing):
  ```
  http://localhost:3000/auth/callback
  http://localhost:3000/**
  mimamori://auth/callback
  mimamori://**
  ```

> **Mobil APK:** Google login `localhost:3000` ga o'tsa — `mimamori://auth/callback` Redirect URLs da yo'q. Yuqoridagi 2 qatorni qo'shing va **Save** bosing.

Kodda `redirectTo` avtomatik: `window.location.origin + '/auth/callback'` — qo'lda port yozish shart emas.

---

## Qadam 3: Tekshirish

1. Brauzer cache tozalang yoki **Incognito** oching
2. `npm run dev` → http://localhost:3000
3. **Continue with Google** bosing
4. Google hisob tanlang → `/setup-profile` ga o'tishi kerak

---

## "Unable to exchange external code" xatosi

Bu xato **Google Cloud emas**, ko'pincha **Supabase → Google Provider** da Client ID/Secret noto'g'ri qo'yilganda chiqadi.

1. Google Cloud → **Credentials** → OAuth client oching
2. **Client ID** va **Client Secret** ni qayta copy qiling
3. Supabase → **Authentication → Providers → Google** — eskisini o'chirib yangisini qo'ying → **Save**
4. 2–5 daqiqa kutib, **Incognito** da qayta sinang

Google Cloud redirect URI (o'zgarmaydi):
```
https://osctnkthrlxxxvxkjmzq.supabase.co/auth/v1/callback
```

Boshqa sabablar:

| Sabab | Yechim |
|---|---|
| Redirect URI noto'g'ri | Google da faqat Supabase callback URL bo'lsin |
| Client Secret xato | Qayta nusxalab Supabase ga joylang |
| OAuth Testing rejimi | Test users ga email qo'shing |
| Boshqa Supabase loyiha | `.env` dagi URL bilan Google sozlamasi bir xil bo'lsin |
| Client ID noto'g'ri tip | **Web application** bo'lishi kerak, Android/iOS emas |

---

## .env tekshiruvi

`Kodokushi/.env`:
```
VITE_SUPABASE_URL=https://osctnkthrlxxxvxkjmzq.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGci...
```

URL dagi project ref Google redirect URI bilan **bir xil** bo'lishi shart.
