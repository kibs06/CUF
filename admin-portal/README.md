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

## Test

```bash
npm test
```

Node's own test runner (`node --test`) over the pure rules in `src/lib/` — no test framework and no extra dependency. `.github/workflows/admin-portal.yml` runs it, plus `npm run build`, on every push that touches this folder.

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

## When a request is refused

Every failure is classified before it reaches a screen, so the portal can say what to *do* rather than only what happened (`src/lib/errors.js`, tested by `npm test`):

| The server sent | What the page says |
|---|---|
| `42501` | the session is not an admin's — sign out and back in |
| `PGRST301` / `401` / "JWT expired" | the session expired; nothing was sent |
| `42804`, `42883`, `42P01`, `PGRST202` | the database is behind this build — apply the migration |
| `PGRST200`, `PGRST204`, `42703` | the page and the database have drifted apart |
| a fetch failure | the server is unreachable; nothing was sent |
| anything else | the server's own words, verbatim |

The raw server text is never discarded — it travels as `detail` and is printed under the sentence whenever it differs from it, because a screenshot of the server's words is often the only route to a fix.

And a queue that comes back **empty** is checked against `device_gate_open()` before the page calls it "nothing waiting": the device gate hides *rows* instead of raising, so a gated session and an idle queue look identical from the client.

## Publishing a model from the portal

The `/model-requests` queue does not only *point at* a model — an admin can publish one and close the ask in the same step. Off unless `VITE_ADMIN_MODEL_UPLOAD=true` is set in `.env` (see `src/lib/constants.js`), matching the app's own "ships dark" convention for this pipeline.

Two sources, because a browser and a phone are not the same client: a **file picker** for a `.glb` on disk (reliable), and a **link** (what the Flutter sheet uses, since no picker dependency can select a `.glb` there). A link download can be refused by the host's CORS rules, and the refusal says so.

The **declaration** — the model's external length in millimetres, and optionally an EU size — is enforced exactly as the Flutter upload sheet enforces it (`src/lib/modelPublish.js`, tested against the migration that owns the numbers):

- the length is written in **millimetres, not centimetres** — `27` is refused as a likely `270`, because 27 mm is not a shoe;
- the band is the column's own: 100–400 mm, and 22–48 EU;
- a size with no length is refused, since the size alone cannot be checked against the mesh;
- a length that disagrees with the seller's measurement by more than ±5 mm is a **warning, not a gate** — the seller measured the outside of a shoe, and a last is not a shoe;
- the request's own measurement is prefilled, so the field starts at the seller's number rather than empty.

It is **not** a third implementation of the 11-check authoring contract: the Dart reference and the TypeScript mirror inside `validate-shoe-model` already cover those rules, so the portal sends the bytes, asks the server, and shows the server's answer. A refusal arrives with the failing rows named, the row stays hidden as a `draft`, and the ask stays open.

Only a live model can close an ask, so a publish has three endings: **closed**, **not live** (refused — the reason is shown and the modal stays open), and **live but still open** (the model passed the server, the close failed; this one is toasted as an error because somebody has to act on it).

Publishing needs the model-request flow applied to the live database (`supabase/migrations/20260928140000_add_shoe_model_requests.sql`) — see `supabase/MIGRATIONS_LIVE_STATUS.md`.

## The other end of the loop: the seller is told (P3)

Closing an ask — fulfilled *or* declined — writes the seller a notice, and it is written by the **database**, inside the same transaction as the status change, so "closed" and "told" cannot disagree. The portal does not send it, and cannot skip it.

It lands on **two channels**, which is a fix rather than thoroughness: `public.notifications` is the per-user feed, and the seller app never renders it — a seller's shell reads `public.seller_notifications`, keyed by store. A notice on one channel only was correct and unreadable at the same time.

What the portal says per ending (`src/lib/askDelivery.js`, tested by `npm test`):

| How it ended | What the admin is told |
|---|---|
| closed | the seller has been told, and the notice quotes the admin's note as "From the team: …" |
| not live | nobody was told — nothing went live and the ask is untouched |
| live but open | nobody was told *yet* — the ask is still open, so no notice was written |
| declined | the seller has been told, and the notice quotes the reason verbatim |

The portal can never fall back to an empty promise: it **never inserts a notice itself** and **never closes an ask by writing the row**, only through the RPCs that notify. Both are guarded mechanically by `src/lib/askDelivery.contract.test.js`, which reads the migration as well as the portal's own source, so the sentence "the seller has been told" fails CI if the SQL behind it moves.

It will not pretend to show you the notice: both notice tables grant SELECT to the recipient alone and no admin policy exists, so no timestamp here would be readable. The page says that instead of inventing one.

## Pages

| Route | Description |
|-------|-------------|
| `/login` | Admin-only login |
| `/` | Dashboard with stats, recent applications & orders |
| `/users` | User management |
| `/seller-applications` | Approve/reject seller applications |
| `/products` | Product catalog management |
| `/model-requests` | 3D model requests filed by sellers: claim, publish a model and close in one step (P2, dark by default), close as done against a live model, decline with a reason — and the seller is told in both closing cases (P3) |
| `/orders` | Order management |
| `/transactions` | GCash/PayMongo payment transactions (read-only) |
| `/analytics` | Charts and trends |
| `/settings` | Admin profile & password |
