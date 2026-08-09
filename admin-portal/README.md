# SoleVision Admin Portal

Web-only admin dashboard for SoleVision. Connects to the same Supabase project as the Flutter mobile app.

## Setup

```bash
cd admin-portal
npm install
cp .env.example .env
```

Edit `.env` with your Supabase credentials (same as the Flutter app):

```
VITE_SUPABASE_URL=https://psczvbfoybqhjeqssimw.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key_here
```

## Run

```bash
npm run dev
```

Open http://localhost:5173 and sign in with an admin account (`profiles.role = 'admin'`).

## Build

```bash
npm run build
npm run preview
```

## Supabase requirements

- Admin RLS policies on `profiles`, `orders`, and `products` (see project prompt)
- Optional: add `suspended` boolean column on `profiles` for user suspension
- Optional: add `rejection_reason` text column on `profiles` for seller rejections
- Enable Realtime on `profiles` table for live seller application updates

## Pages

| Route | Description |
|-------|-------------|
| `/login` | Admin-only login |
| `/` | Dashboard with stats, recent applications & orders |
| `/users` | User management |
| `/seller-applications` | Approve/reject seller applications |
| `/products` | Product catalog management |
| `/orders` | Order management |
| `/transactions` | GCash/PayMongo payment transactions (read-only) |
| `/analytics` | Charts and trends |
| `/settings` | Admin profile & password |
