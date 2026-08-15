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
| Error handling | Custom class-based `ErrorBoundary` |

## Project Structure

```
admin-portal/
├── index.html                  # Vite entry
├── vite.config.js              # React plugin only
├── tailwind.config.js          # Brand theme (colors, fonts)
├── postcss.config.js
├── .env                        # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
├── supabase/
│   └── admin_policies.sql      # RLS policies + optional columns
└── src/
    ├── main.jsx                # Bootstrap: QueryClient + Router + Providers
    ├── App.jsx                 # Route table
    ├── index.css               # Tailwind + base styles
    ├── lib/
    │   ├── supabase.js         # Single shared Supabase client
    │   └── constants.js        # Roles, statuses, formatters, SVG logo
    ├── hooks/                  # Data-access layer (React Query)
    │   ├── useAuth.jsx         # Auth context provider + hook
    │   ├── useDashboard.js     # Stats, recent lists, sparkline, approve/reject
    │   ├── useUsers.js         # Users grouped by role; suspend/reactivate + role-change mutations
    │   ├── useUserDetail.js    # Per-user order history + seller portfolio (detail modal tabs)
    │   ├── useSellerApplications.js  # Applications + realtime subscription
    │   ├── useProducts.js      # Products grouped by store, mutations
    │   ├── useOrders.js        # Orders + status updates
    │   ├── useTransactions.js  # GCash/PayMongo intents + webhook events
    │   └── useAnalytics.js     # Time-series aggregation for charts
    ├── pages/                  # One component per route
    │   ├── Login.jsx
    │   ├── Dashboard.jsx
    │   ├── Users.jsx
    │   ├── SellerApplications.jsx
    │   ├── Products.jsx
    │   ├── Orders.jsx
    │   ├── Reports.jsx
    │   ├── Analytics.jsx
    │   └── Settings.jsx
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
        └── users/, products/   # Feature-specific components
            ├── UserSection, UserRow, UserDetailModal
            └── StoreGroup, ProductCard, ProductListRow,
                ProductDetailModal, AddProductModal
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
| `/orders` | Orders | Order list w/ nested items; status updates |
| `/transactions` | Transactions | Read-only GCash/PayMongo payments: summary cards, filters, detail modal w/ webhook event timeline, CSV export |
| `/reports` | Reports | Report moderation (priority badge in sidebar) |
| `/analytics` | Analytics | Charts: orders/revenue/users over time, status, top products, seller trend |
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

## Styling

- Tailwind with a custom brand palette in `tailwind.config.js`: `primary #8B5A2B`, `secondary #3B2314`, `accent #4ECDC4`, `surface #F5F0EB`, error `#D64545`.
- Fonts: Playfair Display (display), DM Sans (sans), JetBrains Mono (mono).
- Most components use hard-coded hex values (`text-[#3B2314]`) in addition to the configured palette.
- Responsive: sidebar becomes a slide-over with a backdrop on `lg:` breakpoint down.

## Environment & Build

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
```

- `npm run dev` → local dev server (port 5173).
- `npm run build` → static bundle in `dist/` (hostable on any static host, e.g. Netlify/Vercel).
- `npm run preview` → serve the built bundle locally.
- No tests or lint config are currently present.

## Database Entities Used

- `profiles` — users, roles, `seller_status`, `suspended` + `suspended_reason`/`suspended_at` (suspension audit trail), `rejection_reason`
- `stores` — store metadata per seller
- `products` — listings with `is_published`, relations to `stores`
- `product_images` — images per product (`is_primary`, `display_order`)
- `inventory` — stock per product size
- `orders` — customer/store/total/status
- `order_items` — line items joined to products
- `reports` — user reports with `priority` (`high`) and `status`

## Known Notes / Caveats

- Charts use full-table reads and client-side aggregation — fine at small scale, but heavy at scale.
- `reports` RLS assumes the mobile app's policies allow admin reads; no admin-specific `reports` policy exists in `admin_policies.sql`.
- Realtime for `profiles` must be enabled in the Supabase dashboard (`ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles`).
- `dist/` is committed to the repo; it can be regenerated with `npm run build`.
- **Admin suspension enforcement** lives in `supabase/migrations/20260813000000_admin_suspension_enforcement.sql` (RLS hard-ban: `is_admin()`/`is_seller_or_admin()` exclude suspended accounts, `is_suspended()` write blocks, guard triggers). It must be applied to the DB **before** the Users page loads (it selects `suspended_reason`/`suspended_at`) — see `supabase/MIGRATIONS_LIVE_STATUS.md`. Full-stack reference: `docs/AI/ADMIN_SUSPENSION_ARCHITECTURE.md`.
