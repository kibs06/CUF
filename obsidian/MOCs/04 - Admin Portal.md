# 🛡️ Admin Portal

> The React (Vite + Tailwind) admin console: dashboard, users, seller applications, products, orders, analytics, transactions, suspension. **#moc**

---

## 📌 Overview

**Two admin surfaces** sharing the same Supabase backend:
1. **React Web SPA** (`admin-portal/`) — Vite + Tailwind + TanStack Query; charts client-computed.
2. **Flutter Mobile Admin** (`lib/screens/admin/`) — `AdminShell` with dashboard, user management, product monitoring, seller approval, analytics, orders, reports, transactions, deletion requests, settings.

**Security boundary is Supabase RLS** — neither surface uses the service-role key.

**Stack:** React 18 (JSX) · Vite 6 · react-router-dom v6 · TanStack Query v5 · React Context (Auth/Toast) · Supabase JS v2 · Tailwind 3 · lucide-react · recharts · motion · class-based `ErrorBoundary`.

---

## 🗺️ Data flow (layer model)

```
Pages (src/pages/*) ──> Hooks (src/hooks/*) ──> lib/supabase.js ──> Supabase (REST + Realtime)
   │                        │                        │
   UI state, toasts    only place that touches   single shared client
                       supabase besides useAuth  (anon key, admin session)
```

- **React Query**: one `QueryClient` (`staleTime: 30s`, `retry: 1`); namespaced keys (`['dashboard-stats']`, `['admin-users']`, `['seller-applications', status]`, `['analytics', days]`); mutations invalidate dependent keys (approving a seller invalidates applications + recent-pending + dashboard-stats + users).
- **AuthProvider** (`useAuth.jsx`) — session/profile/loading/`accessDenied`/signIn/signOut/refreshProfile; subscribes to `onAuthStateChange`.
- **ToastProvider** — `showToast(message, type)`, 3.5s auto-dismiss.

---

## 🔐 Auth & authorization

1. `Login.jsx` → `supabase.auth.signInWithPassword`.
2. Profile fetched from `profiles` by `auth.uid()`.
3. Not an **active admin** (`role !== 'admin'` **or** `suspended === true`) → session signed out + `accessDenied` — suspended admin loses console access immediately.
4. `ProtectedRoute` (all pages except `/login`) → redirect to `/login` when no session or `!isAdmin`; spinner while loading.
5. **RLS is the real gatekeeper** — `admin_policies.sql` defines SELECT/UPDATE policies on `profiles`/`orders`/`products` via `EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')`.

---

## 🗺️ Routes (React Web SPA)

| Route | Page | Purpose |
|-------|------|---------|
| `/login` | Login | Admin sign-in |
| `/` | Dashboard | Stat cards, recent applications/orders, 7-day sparkline |
| `/users` | Users | Users grouped by role (All/Customers/Sellers/Admins), search, detail modals |
| `/seller-applications` | SellerApplications | Approve/reject pending sellers (realtime) |
| `/products` | Products | Catalog grouped by store; toggle publish, delete (soft) |
| `/orders` | Orders | Order list w/ nested items; status updates; "View Payment" → transactions |
| `/transactions` | Transactions | Read-only GCash/PayMongo: summary cards, filters, detail modal w/ webhook timeline, CSV export |
| `/reports` | Reports | Report moderation (priority badge in sidebar, 60s poll) |
| `/analytics` | Analytics | Orders/revenue/users over time, status pie, top products, seller trend |
| `/settings` | Settings | Admin profile & password |

## 📱 Flutter Mobile Admin (`lib/screens/admin/`)

| Screen | File | Purpose |
|--------|------|---------|
| Admin Shell | `admin_shell.dart` | Tab host for all admin screens |
| Dashboard | `admin_dashboard_screen.dart` | Overview stats, quick actions |
| Manage Users | `manage_users_screen.dart` | User list with role filters, suspension |
| Monitor Products | `monitor_products_screen.dart` | Product catalog oversight |
| Seller Approval | `seller_approval_screen.dart` | Tier 1 queue + Business Docs tab |
| Business Docs Review | `seller_business_docs_review_screen.dart` | Tier 2 doc review (signed URLs) |
| Analytics | `admin_analytics_screen.dart` | Orders/revenue/users over time |
| Orders | `admin_orders_screen.dart` | Order management and status updates |
| Reports | `admin_reports_screen.dart` | Report moderation |
| Transactions | `admin_transactions_screen.dart` | GCash/PayMongo transaction history |
| Deletion Requests | `manage_deletion_requests_screen.dart` | Account deletion request management |
| Settings | `admin_settings_screen.dart` | Admin profile & password |

---

## 🧩 Key features

### Users & suspension (`Users.jsx` + `UserRow.jsx` + `UserDetailModal.jsx`)
- Suspended rows: red tint + "Suspended" pill. Filters: **All / Active / Suspended** (client-side).
- **UserDetailModal tabs**:
  - **Account** — member since, ID, phone, seller status, suspension banner (reason + date), **Admin Actions**: *Change role* + *Suspend / Reactivate* (reason textarea on suspend).
  - **Orders** (customers) — `useUserOrders(userId)`: full order history (store, item count, payment method, status badge, total).
  - **Business** (sellers) — `useSellerPortfolio(sellerId)`: owned stores (open/closed/deactivated), KPI grid (online orders/revenue, POS sales/revenue, products, total revenue), product listings.
- Hooks: `useUsers` (grouped by role, includes `suspended, suspended_reason, suspended_at`), `useUpdateUserStatus` (suspend w/ reason / reactivate clears all three), `useUpdateUserRole` (customer/seller/admin), `useUserOrders`, `useSellerPortfolio`.
- **DB refuses to demote/suspend your own account or the last active admin** (guard triggers) — errors surface in the modal as expected behavior.

### Seller approval
`useApproveSeller`/`useApproveApplication` set `role: 'seller'` + `seller_status: 'approved'`; rejection sets `seller_status: 'rejected'` + optional `rejection_reason`. **Realtime**: subscribes to `postgres_changes` on `profiles` filtered `seller_status=eq.pending` (requires Realtime enabled on `profiles`).

### Transactions (GCash/PayMongo)
Read-only on `payment_intents` + `payment_webhook_events` (SELECT-only RLS in `20260810000000_admin_transactions_view.sql`). Detail modal: fee breakdown (Model B surcharge, PayMongo fee, net), webhook event timeline (payload behind explicit toggle), CSV export (client-side, BOM-prefixed for Excel). `/transactions?order=<id>` deep link from Orders "View Payment".

### Products
`useProducts` groups by store ("Unassigned" fallback), computes stock totals, thumbnails, category list client-side. **Delete is soft** — `is_published: false`.

---

## 🗄️ Database entities used

`profiles` (roles, seller_status, suspended + suspended_reason/suspended_at, rejection_reason) · `stores` · `products` + `product_images` + `inventory` · `orders` + `order_items` · `payment_intents` + `payment_webhook_events` · `reports` (priority/status).

## ⚠️ Gotchas

1. **Deploy order matters**: apply `20260813000000_admin_suspension_enforcement.sql` **before** deploying the portal — `useUsers.js` selects `suspended_reason`/`suspended_at`, and PostgREST 400s on missing columns (the original failure mode, fixed 2026-08-12).
2. `admin_policies.sql` must keep the `NOT COALESCE(suspended, false)` body in `is_admin()` or re-applying it silently downgrades the ban.
3. Charts do full-table reads + client-side aggregation — fine at small scale, heavy at scale.
4. `reports` RLS assumes the mobile app's policies allow admin reads — no admin-specific reports policy exists.
5. Realtime for `profiles` must be enabled in the Supabase dashboard (`ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles`).
6. `dist/` is committed to the repo; regenerate with `npm run build`. No tests or lint config present.

## 📚 Deep-dive docs

- [[admin-portal/docs/architecture|🏛️ Admin portal architecture]] — the canonical portal doc
- [[docs/AI/ADMIN_SUSPENSION_ARCHITECTURE|⛔ Admin suspension & enforcement]] — full three-layer reference
- [[docs/PHASE1_5_SECURITY_AUDIT|Security audit (Phase 1–5)]]
- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary — admin flow]]
- [[docs/PROJECT_HANDOFF|📄 Project Handoff — admin portal decisions]]

## 🔗 Related

- [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth & Accounts]] — roles, suspension
- [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database & Supabase]] — RLS, migrations
