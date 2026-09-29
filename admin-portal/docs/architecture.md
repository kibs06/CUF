# SoleVision Admin Portal — Architecture

Web-only admin dashboard for the SoleVision e-commerce platform. It shares the same Supabase backend as the Flutter mobile app but is a fully independent React frontend.

## High-Level Overview

```
┌─────────────────────────────────────────────┐
│  Browser (React SPA, Vite build)            │
│                                             │
│  Pages ──> Hooks (React Query) ──> supabase │
│  Layout/UI components      (REST + Realtime)│
│                                             │
└──────────────┬──────────────────────────────┘
               │ HTTPS (Supabase client JS)
               ▼
┌─────────────────────────────────────────────┐
│  Supabase                                   │
│  • Auth (email/password)                    │
│  • Postgres (profiles, stores, products,    │
│    orders, order_items, inventory, reports) │
│  • RLS policies (admin-only access)         │
│  • Realtime (profiles table)                │
└─────────────────────────────────────────────┘
```

- **SPA only** — no SSR; all data fetching happens client-side.
- **Security boundary is Supabase RLS** — the app never uses the service-role key; it authenticates as the signed-in admin with the anon key.
- **Charts** are client-computed from raw query results (no SQL aggregation endpoints).

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | React 18 (JSX, no TypeScript) |
| Build tool | Vite 6 |
| Routing | react-router-dom v6 |
| Server state | @tanstack/react-query v5 |
| Client state | React Context (`AuthProvider`, `ToastProvider`) |
| Backend | Supabase (`@supabase/supabase-js` v2) |
| Styling | Tailwind CSS 3 + custom theme |
| Icons | lucide-react |
| Charts | recharts |
| Animation | motion (Motion/Framer Motion successor) |
| Shaders | Hand-written WebGL 1 (GLSL ES 1.00), no dependency |
| Error handling | Custom class-based `ErrorBoundary` |

## Project Structure

```
admin-portal/
├── index.html                  # Vite entry
├── vite.config.js              # React plugin only
├── tailwind.config.js          # Brand theme (colors, fonts)
├── postcss.config.js
├── .env                        # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY,
│                               #   optional VITE_ADMIN_MODEL_UPLOAD (P2, off by default)
├── supabase/
│   └── admin_policies.sql      # RLS policies + optional columns
└── src/
    ├── main.jsx                # Bootstrap: QueryClient + Router + Providers
    ├── App.jsx                 # Route table
    ├── index.css               # Tailwind + base styles
    ├── lib/
    │   ├── supabase.js         # Single shared Supabase client
    │   ├── constants.js        # Roles, statuses, formatters, SVG logo
    │   ├── errors.js           # Refusal classification: code → sentence + detail (see “Failed requests”)
    │   ├── errors.test.js      # Tests for those rules; run by `npm test`
    │   ├── modelPublish.js     # The publish rules, ported from the Flutter upload sheet (see “Publishing a model”)
    │   ├── modelPublish.test.js         # Tests for those rules
    │   ├── modelPublish.contract.test.js # Reads the numbers back out of the migration that owns them
    │   ├── askDelivery.js      # Whether a closing action told the seller, and in what words (see “The other end of the loop”)
    │   ├── askDelivery.test.js          # Tests for those claims
    │   ├── askDelivery.contract.test.js # Reads the SQL — and this portal's own source — to keep the claim true
    │   ├── aiBlob.js           # The AI blob's props, palettes and motion profiles (see “The AI page”)
    │   └── aiBlob.test.js      # Tests for those rules — no GL context needed
    ├── hooks/                  # Data-access layer (React Query)
    │   ├── useAuth.jsx         # Auth context provider + hook
    │   ├── useDashboard.js     # Stats, recent lists, sparkline, approve/reject
    │   ├── useUsers.js         # Users grouped by role; suspend/reactivate + role-change mutations
    │   ├── useUserDetail.js    # Per-user order history + seller portfolio (detail modal tabs)
    │   ├── useSellerApplications.js  # Applications + realtime subscription
    │   ├── useProducts.js      # Products grouped by store, mutations
    │   ├── useOrders.js        # Orders + status updates
    │   ├── useTransactions.js  # GCash/PayMongo intents + webhook events
    │   ├── useAnalytics.js     # Time-series aggregation for charts
    │   ├── useModelRequests.js # The 3D model-request queue + its three closing RPCs
    │   ├── usePublishModel.js  # P2: bytes → bucket → draft row → `validate-shoe-model` → close
    │   └── useDeviceGate.js    # `device_gate_open()` — “empty” vs “hidden”, for gated tables
    ├── pages/                  # One component per route
    │   ├── Login.jsx
    │   ├── Dashboard.jsx
    │   ├── Users.jsx
    │   ├── SellerApplications.jsx
    │   ├── Products.jsx
    │   ├── Orders.jsx
    │   ├── Reports.jsx
    │   ├── Analytics.jsx
    │   ├── Settings.jsx
    │   ├── Ai.jsx              # Ai Fluid Blob: live demo, the five states, usage, props (reads no data)
    │   └── ModelRequests.jsx   # 3D model queue: claim / close against a live model / decline
    └── components/
        ├── ErrorBoundary.jsx
        ├── layout/             # App shell
        │   ├── AppLayout.jsx   # Sidebar + TopBar + <Outlet/>
        │   ├── Sidebar.jsx     # Nav + user card + logout + report badge
        │   ├── TopBar.jsx
        │   └── ProtectedRoute.jsx  # Auth gate
        ├── ui/                 # Reusable primitives
        │   ├── AvatarInitials, Badge, DataTable, EmptyState, Modal,
        │   ├── Skeleton, StatCard, Toast
        ├── users/, products/   # Feature-specific components
        │   ├── UserSection, UserRow, UserDetailModal
        │   └── StoreGroup, ProductCard, ProductListRow,
        │       ProductDetailModal, AddProductModal
        ├── model-requests/     # UploadModelModal — the P2 publish-then-close dialog
        └── ai/                 # AiFluidBlob.jsx (canvas + loop) and its blobShader.js
                                # (the GLSL), with blobShader.test.js pinning the uniform names
```

## Data Flow (Layer Model)

1. **Pages** (`src/pages/*`) — route-level components. Own UI state, call hooks, render feature components, show toasts.
2. **Hooks** (`src/hooks/*`) — the only place that touches `supabase` besides `useAuth`. Encapsulate queries, mutations, and cache invalidation.
3. **lib/supabase.js** — single shared client instance from env vars.
4. **Backend** — Supabase Postgres with RLS enforcing that only `role = 'admin'` users can read/update `profiles`, `orders`, and `products`.

Pages never talk to Supabase directly — a few exceptions exist (e.g. `Reports.jsx` defines local query hooks, `Sidebar.jsx` polls the `reports` table) but the pattern is hook-driven.

### Server State (React Query)

- One `QueryClient` created in `main.jsx` with `staleTime: 30s`, `retry: 1`.
- Every query key is namespaced per feature, e.g. `['dashboard-stats']`, `['admin-users']`, `['seller-applications', status]`, `['orders']`, `['analytics', days]`.
- Mutations invalidate dependent keys on success, e.g. approving a seller invalidates `['seller-applications']`, `['recent-pending-applications']`, `['dashboard-stats']`, `['users']`.

### Failed requests (why a refusal is classified)

`src/lib/errors.js` turns whatever the server sent into a sentence *and* keeps the server's own words. A client that cannot tell why it was refused has no move: it retries what will never work, or gives up on what a reload would fix. This is the portal's half of a rule the database side had to learn in the same week — a `RAISE EXCEPTION` with no ERRCODE reports `P0001`, which is indistinguishable from a bug inside the function.

| Code the server sent | Kind | What the admin is told |
|---|---|---|
| `42501` | `not_admin` | the session is not an admin's → sign out and back in |
| `PGRST301`, `PGRST302`, `401` | `session_expired` | the session expired; nothing was sent |
| `42804`, `42883`, `42P01`, `3F000`, `PGRST202`, `PGRST205` | `db_behind_code` | the database is behind this build → apply the migration |
| `PGRST200`, `PGRST204`, `42703`, `42P10` | `schema_drift` | the page and the database have drifted apart |
| (no code; a fetch failure) | `offline` | the server is unreachable; nothing was sent |
| anything else | `unknown` | the server's message, verbatim |

`42501` means **not an admin** and nothing else: it is what the model-request RPCs' `is_admin()` guards raise deliberately, after they were fixed to carry an ERRCODE at all. Hooks wrap with `toPortalError(error, fallback)` rather than `new Error(error.message)`, because the code lives on the object and a message-only copy destroys the one field that decides the sentence. The raw text travels as `detail` and is printed whenever it differs from that sentence.

**A gated table looks empty, not refused.** The device gate's policy is `USING (device_is_trusted() OR is_admin())`, and a policy like that hides *rows* instead of raising — so "nothing waiting" and "this session cannot see the queue" are the same response from PostgREST. `useDeviceGate()` asks `public.device_gate_open()`, the function that exists for exactly this (its comment: distinguish "empty" from "gated"), and the queue says which one it is. The probe never throws, and reports `null` for unknown: a probe whose job is to explain a blank screen must not be able to blank it.

### Publishing a model (P2 — publish and close in one step)

Roadmap V2.11's P2, and the action the queue was missing: without it “Close as done” could only ever point at a model somebody else had already published. `usePublishModel.js` runs the same pipeline as `ShoeModelUploadService.publish` in the app, in the same order, for the same reasons:

1. **the bytes and their digest** — from a picked file (checked for size *before* being read into memory) or a link;
2. **the object first, the row second** — a row whose object is missing renders as “no model”, while an object with no row is simply invisible;
3. **the row lands as a `draft`, never `active`** — between the insert and the server's answer the only state the catalog can observe is a hidden one;
4. **`validate-shoe-model` judges the stored bytes** — the function is the only caller the database lets write `status = 'active'` (V2.4), and it resolves `is_admin()` through the caller's own client;
5. **the close runs last** — the fulfil RPC requires an `active` model of the same product, so it is attempted only when there is something to point at.

**The declaration rules are the sheet's, not a new set.** `modelPublish.js` mirrors `lib/utils/shoe_model_upload.dart`: the length is in **millimetres not centimetres** (a `27` is refused as a likely `270`), the band is the column's own 100–400 mm, a size without a length is refused, and a length more than ±5 mm from the seller's measurement is a **warning, not a gate**. `modelPublish.contract.test.js` reads that band, the EU band, the bucket's 8 MB cap, its `allowed_mime_types`, and the three admitted `status` values straight out of `20260927180000_add_try_on_models.sql`, so a rule that drifts fails the test rather than reaching an admin as a wrong refusal.

**What is deliberately not ported: the 11-check authoring contract.** That contract already has two implementations — the Dart reference and the TypeScript mirror inside `validate-shoe-model`, parity-checked over 22 fixtures — and a third would be a third place for eleven rules to drift. The app's client-side run is a courtesy that saves a round trip; the server is the authority. So the portal uploads, asks, and shows the server's answer: a refusal names the failing rows, the row stays a hidden draft, and the ask stays open.

**Two sources, because a browser is not a phone.** The app has no file picker (no dependency can select a `.glb`), so a link is its only source; a browser gets a picker for free and is also the one client whose link downloads can be refused by the host's CORS rules. Both feed the same pipeline.

**Three endings, and the third is the one that matters.** *closed* — the model is live and the ask is fulfilled; *not live* — the server refused it, the reason is shown and the dialog stays open; *live but still open* — the model passed the server and the close failed, so the modal reports it and the toast treats it as an error, because a live model with a waiting seller is a state somebody has to act on, not a state to report as success.

The whole surface is behind `MODEL_UPLOAD_ENABLED` (`lib/constants.js`), off unless `VITE_ADMIN_MODEL_UPLOAD=true`. Two reasons for that, and the second is the interesting one: the app's reason is that nothing can go live by accident while the path ends at the server; the portal's extra reason is that this path also needs the request-flow migration applied to the live project (`20260928140000`), and until that happens a publish here would fail in a way that reads like a bug in this page.

### The other end of the loop (P3 — the seller is told)

P2 let the queue *answer* an ask. Answering told nobody, which is the same gap one level down: the seller's stateful row in the product action sheet only speaks to a seller who opens it, and a week of somebody else's work is long enough for them to file the same ask twice.

That half is built, and it is built **in the database**: `fulfil_shoe_model_request` and `decline_shoe_model_request` write the seller's notice inside the transaction that closes the ask, so "closed" and "told" cannot disagree. This page does not send it. An app-side send was rejected for the reason the app's own phase gives — a notice a client can decline to send is a courtesy rather than a fact — and every client would have to remember.

**Two channels, because one was correct and unreadable at the same time.** `public.notifications` is the generic per-user feed; a seller's session lands in `SellerShell`, whose bell reads `public.seller_notifications`, keyed by store. So each closing RPC writes both rows, and the portal's sentence names both, because a claim that covers one of two channels is the bug V2.14 had to go and fix.

**What the page says, per ending.** `askDelivery.js` decides, and `askDelivery.contract.test.js` keeps it honest:

| How it ended | Delivery | Why |
|---|---|---|
| closed | told | the RPC wrote both notices after the `UPDATE`, in one plpgsql body — one transaction |
| not live | not told | nothing went live and the ask is untouched, so there is nothing to tell |
| live but open | not told *yet* | the ask is still open, so no notice exists — the one ending a green tick would have hidden |
| declined | told, with the reason | the RPC quotes `p_reason` verbatim, and this page refuses to send a blank one |

**Three things the portal is not allowed to do**, each guarded by reading its own source:

- send a notice itself — the RPC is the writer, and a second sender would deliver twice while the fact stayed the RPC's;
- close an ask by writing `shoe_model_requests` — the closing RPCs are the only path, which is also what makes "closed ⇒ told" structural rather than hopeful;
- claim a delivery it cannot see. Both notice tables grant SELECT to the recipient alone and **no admin policy exists**, so "told at 14:02" is unreadable from this session and would have to be invented. `NOTICE_NOT_READABLE_SENTENCE` says so in the dialog instead.

**The honest limit of the guard:** it reads the migration file, not the live project. `20260928140000` was hand-applied to the live database in an **older revision** and must be re-applied (see `supabase/MIGRATIONS_LIVE_STATUS.md`), and a close against that older revision writes no notice at all — which is why this phase's claim is pinned to the file CI applies, and why both switches stay off until the re-apply is done.

### Client State (Context)

- **`AuthProvider`** (`useAuth.jsx`) — session, profile, `loading`, `accessDenied`, `signIn`, `signOut`, `refreshProfile`. Subscribes to `supabase.auth.onAuthStateChange`.
- **`ToastProvider`** (`components/ui/Toast.jsx`) — `showToast(message, type)` with auto-dismiss (3.5s).

## Authentication & Authorization

1. `Login.jsx` calls `signIn(email, password)` → `supabase.auth.signInWithPassword`.
2. After auth, the profile row is fetched from `profiles` by `auth.uid()`.
3. If the profile is not an **active** admin (`role !== 'admin'` **or** `suspended === true`), the session is signed out and `accessDenied` is set — the portal is admin-only, and a suspended admin loses console access immediately.
4. `ProtectedRoute` (wraps all pages except `/login`) redirects to `/login` when there is no session or `isAdmin` is false, showing a spinner while `loading`.
5. **RLS is the real gatekeeper**: `supabase/admin_policies.sql` defines SELECT/UPDATE policies on `profiles`, `orders`, and `products` using `EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')`. The `reports` table is guarded by the mobile app's existing policies (implied by use).

## Routing

Defined in `App.jsx`:

| Route | Page | Purpose |
|---|---|---|
| `/login` | Login | Admin sign-in |
| `/` | Dashboard | Stat cards, recent applications/orders, 7-day sparkline |
| `/users` | Users | Users grouped by role (customer/seller/admin) |
| `/seller-applications` | SellerApplications | Approve/reject pending sellers |
| `/products` | Products | Catalog grouped by store; toggle publish, delete |
| `/model-requests` | ModelRequests | The 3D model request queue (waiting badge in sidebar): claim, **publish a model and close in one step** (P2, dark by default), close as done against a live model, decline with a reason — the seller is told on both closing paths (P3) |
| `/orders` | Orders | Order list w/ nested items; status updates |
| `/transactions` | Transactions | Read-only GCash/PayMongo payments: summary cards, filters, detail modal w/ webhook event timeline, CSV export |
| `/reports` | Reports | Report moderation (priority badge in sidebar) |
| `/analytics` | Analytics | Charts: orders/revenue/users over time, status, top products, seller trend |
| `/ai` | Ai | Ai Fluid Blob: the AI voice-assistant visual — live prop controls, the five states side by side, usage and the props table. **Touches no data at all** |
| `/settings` | Settings | Admin profile & password |
| `*` | — | Redirect to `/` |

## Transactions page (GCash/PayMongo)

Read-only visibility into `payment_intents` + `payment_webhook_events` (admin SELECT-only RLS in
`20260810000000_admin_transactions_view.sql`; mirrored in `supabase/admin_policies.sql`).

- `useTransactions.js` fetches intents joined to orders/stores/customers, plus all webhook events
  (matched by `order_id` or `payment_intent_id`), with graceful fallback if the fee columns
  migration hasn't been applied yet.
- Filters: status + date range applied server-side (query key `['transactions', filters]`);
  store/search applied client-side (mirrors `Orders.jsx`).
- Detail modal: fee breakdown (Model B surcharge, PayMongo fee, net), references (mono font),
  order context, and the webhook event timeline (payload viewable only via an explicit toggle).
- CSV export of the currently filtered rows (client-side, BOM-prefixed for Excel).
- `/transactions?order=<id>` deep link auto-opens a transaction — used by the "View Payment"
  button in the `Orders.jsx` detail modal for online GCash orders.
- Animation (motion): staggered page/row entrances, stat count-up, row hover, `AnimatePresence`
  filter transitions, modal scale/fade, timeline stagger, status-change pulse on the badge —
  all respecting `useReducedMotion`; transform/opacity only.

## Key Behaviors / Features

- **Seller approval flow**: `useApproveSeller`/`useApproveApplication` set `role: 'seller'` + `seller_status: 'approved'`; rejection sets `seller_status: 'rejected'` and optionally writes `rejection_reason`.
- **Realtime**: `useSellerApplications` subscribes to `postgres_changes` on `profiles` filtered by `seller_status=eq.pending`, invalidating queries live. Requires Realtime enabled on `profiles` in Supabase.
- **Reports badge**: `Sidebar.jsx` polls `reports` every 60s for high-priority open reports.
- **Product grouping**: `useProducts` groups products by store (with an "Unassigned" fallback), computes stock totals, thumbnails, and category list client-side.
- **Delete is soft**: `useDeleteProduct` sets `is_published: false` rather than deleting rows.
- **User suspension & role management**: `useUsers.js` exposes `useUpdateUserStatus` (suspend with reason / reactivate) and `useUpdateUserRole` (customer/seller/admin). `UserDetailModal` shows Account / Orders (customers) / Business (sellers) tabs plus the Admin Actions. The DB refuses to demote/suspend your own account or the last active admin (guard triggers in `20260813000000_admin_suspension_enforcement.sql`) — those errors surface in the modal as expected behavior.
- **Analytics**: `useAnalytics(days)` fetches raw rows for a date range and builds day buckets, status distributions, top products, and monthly seller-application trends entirely in JS.

## The AI page (a surface with no data)

`/ai` is the only route in this portal that reads nothing: no query, no realtime channel, no rows. It documents and demonstrates **Ai Fluid Blob**, the AI voice-assistant visual — a multi-strand chromatic liquid wave seen through a glass refraction lens — and it is deliberately a *component* page rather than a feature page, so the layer model is satisfied trivially: UI state in the page, drawing in the component, rules in `lib/`.

| File | Owns |
|---|---|
| `pages/Ai.jsx` | which props are on screen: state, the controls, the snippet, the docs prose |
| `components/ai/AiFluidBlob.jsx` | one WebGL context, one program, one quad, and the render loop |
| `components/ai/blobShader.js` | the two GLSL sources — the entire drawing |
| `lib/aiBlob.js` | props, clamping, palettes, the five motion profiles, the snippet — pure, and tested |

### What the picture is made of

Two layers, and both are math on one quad.

**The liquid.** `count` chromatic bands. Each is an almond — wide and bright on the axis and pinched to a point at both ends, because that is what a ring around a sphere looks like from just above its equator — and odd and even bands lean opposite ways, so neighbouring bands cross in the middle rather than nesting. The palette is read off the *position* rather than off whichever band is strongest, because a hue taken from the strongest band makes every crossing a seam and turns the sphere into a collage of flat patches. That is not a theory; it is the first thing this shader did.

**The glass.** The sphere samples that liquid through itself, once per colour channel, pulling the sample toward its own axis harder the further the surface has turned away — dispersion and the magnified, wrapped image at once. On top of that: a saturated rim, one tight sheen, and the bright crescent a glass ball focuses underneath itself.

⚠️ The canvas is **transparent**, and the shader writes straight alpha whose alpha *is* its brightness: a dim tail is a faint tail rather than a dark smudge. An earlier version of this file painted its own near-black stage, which is why it could only ever sit on a dark panel and why it looked nothing like the component it implements. The consequence worth knowing: it composites over anything, and the bright band cores are *saturation*, not added light — adding the liquid's light on top of a pale body drives every channel past 1.0 and clips the band to white.

**The voice orb** at the centre is part of the component, not something the page adds: three DOM bars in a frosted disc, animated by a single CSS keyframe whose two ends are custom properties set per bar. Its sizes and its motion profiles live in `aiBlob.js` with everything else that can be decided without a GPU, which is also what makes `thinking` and `orbit` draw dots rather than bars testable — the idle states are the ones where nothing is being heard.

### The seam that has no compiler

Props become **uniforms by name**, and `gl.getUniformLocation` answers `null` for a name the shader does not declare — after which `gl.uniform1f(null, 0.4)` is a silent no-op. The page renders, nothing logs, and one prop quietly does nothing. That is the one seam in this portal that neither TypeScript, a linter, nor `node --test` could see unaided, so `blobShader.test.js` pins both directions: every uniform the component uploads must be declared, every declared uniform must be uploaded, and the array width must equal the `MAX_STRANDS` the prop clamp enforces.

The same file refuses a backtick in either shader. Both sources are template literals, and this component has shipped the same mistake three times: a comment written with markdown backticks around a prop name, which either fails to parse or — the unlucky case — leaves a balanced pair that parses cleanly and hands the driver a shader with JavaScript spliced through it.

### Why hand-written WebGL, and why ES 1.00

The portal's only graphics dependencies are Tailwind and `recharts`. Adding `ogl` would put a 3D engine in the bundle to draw a shader on a quad, so the drawing is ~200 lines of GLSL instead. It targets **WebGL1** (GLSL ES 1.00), which the component's own first render made worth writing down: ES 1.00 has no integer `max`, so `max(uCount, 1)` fails to compile — and because a compile failure takes the same graceful path as a refused context, the only symptom was a fallback gradient that looked plausible. It was found by reading the DOM (`data-blob-fallback` was present on all six instances), not by looking at the screenshot. The same file also cannot be indexed by expression, which is why the palette lookup is written as a bounded search over the uniform array.

### The loop stops, and reduced motion is one frame

Frames are scheduled only while the canvas is on screen and the document is visible (`IntersectionObserver` plus `visibilitychange`), because a dashboard left open behind another tab should not be a space heater. `prefers-reduced-motion` is treated as *no movement*, not as *no component*: the field is drawn once at a fixed, composed phase (12.5 s, chosen because phase zero is the instant every sinusoid aligns and the strands collapse into a single ring). The rule lives in `aiBlob.js` and is unit-tested; the frozen-but-drawn behaviour was confirmed in a browser with the media query forced.

### Failure is a fallback, not a blank box

A refused context, a lost context and a shader that will not compile are the same visitor experience, so they take the same path: stacked radial gradients in the caller's palette, marked `data-blob-fallback`, with the reason logged. The marker exists so the difference is visible in the DOM rather than only in the pixels — which is exactly how the ES 1.00 defect above was caught.

### ⚠️ Provenance

The published documentation for this component belongs to a Lightswind **Pro** one and ships `// 🔒 Upgrade to Lightswind Pro to unlock full source code & CLI access` where the source would be. What is in this repository is an **independent implementation of the same documented API** — the five props and their defaults are the documented ones, the pixels are ours — and the page states that where an admin reads it, keeping the original install steps labelled as reference rather than rewriting them.

### What proves it works

`npm test` covers the rules and the uniform seam; **nothing automated can cover the pixels**, so the drawing was verified in a real browser: five variants, `count` 4 and 12 (the uniform array width and the palette cycling), `glass` on and off (both shader branches), two sizes with `devicePixelRatio` scaling, and the forced reduced-motion frame. Six contexts mount at once on the page (the demo plus five states), which is also what makes the context budget — and so the decision not to release contexts on unmount — something to keep an eye on if this page ever grows more instances.

## Styling

- Tailwind with a custom brand palette in `tailwind.config.js`: `primary #8B5A2B`, `secondary #3B2314`, `accent #4ECDC4`, `surface #F5F0EB`, error `#D64545`.
- Fonts: Playfair Display (display), DM Sans (sans), JetBrains Mono (mono).
- Most components use hard-coded hex values (`text-[#3B2314]`) in addition to the configured palette.
- Responsive: sidebar becomes a slide-over with a backdrop on `lg:` breakpoint down.

## Environment & Build

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_ADMIN_MODEL_UPLOAD=false   # optional; true gives the queue its “Upload a model” action (P2)
```

- `npm run dev` → local dev server (port 5173).
- `npm run build` → static bundle in `dist/` (hostable on any static host, e.g. Netlify/Vercel).
- `npm run preview` → serve the built bundle locally.
- `npm test` → Node's own runner (`node --test`) over `src/lib/*.test.js`. No test framework and no extra dependency; no lint config is present.

## Database Entities Used

- `profiles` — users, roles, `seller_status`, `suspended` + `suspended_reason`/`suspended_at` (suspension audit trail), `rejection_reason`
- `stores` — store metadata per seller
- `products` — listings with `is_published`, relations to `stores`
- `product_images` — images per product (`is_primary`, `display_order`)
- `inventory` — stock per product size
- `orders` — customer/store/total/status
- `order_items` — line items joined to products
- `reports` — user reports with `priority` (`high`) and `status`
- `shoe_model_requests` — a seller's ask for a 3D model of one product (`external_length_mm` etc., the seller's own measurement), closed by one of three admin RPCs
- `product_models` — the published models, one row per product/version: `storage_path`, `sha256`, `status` (`draft`/`active`/`rejected`), and the author's declared `authored_length_mm`/`authored_size_eu`. Objects live in the public `shoe-models` bucket (8 MB, `model/gltf-binary`)
- `notifications`, `seller_notifications` — the seller's notice on both channels, written by the closing RPCs. **Read-only from here, and not readable at all**: both grant SELECT to the recipient, and the portal only ever names what was written

## Known Notes / Caveats

- Charts use full-table reads and client-side aggregation — fine at small scale, but heavy at scale.
- `reports` RLS assumes the mobile app's policies allow admin reads; no admin-specific `reports` policy exists in `admin_policies.sql`.
- Realtime for `profiles` must be enabled in the Supabase dashboard (`ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles`).
- `dist/` is gitignored build output; regenerate with `npm run build`.
- **Admin suspension enforcement** lives in `supabase/migrations/20260813000000_admin_suspension_enforcement.sql` (RLS hard-ban: `is_admin()`/`is_seller_or_admin()` exclude suspended accounts, `is_suspended()` write blocks, guard triggers). It must be applied to the DB **before** the Users page loads (it selects `suspended_reason`/`suspended_at`) — see `supabase/MIGRATIONS_LIVE_STATUS.md`. Full-stack reference: `docs/AI/ADMIN_SUSPENSION_ARCHITECTURE.md`.
