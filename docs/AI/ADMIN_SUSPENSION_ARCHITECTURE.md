# CUFMAI — Admin Suspension & Enforcement Architecture

> Condensed reference for AI agents working on account suspension / admin
> moderation. Derived from the live codebase:
> `lib/screens/auth_gate.dart`, `lib/providers/auth_provider.dart`,
> `admin-portal/src/hooks/useAuth.jsx`, `admin-portal/src/hooks/useUsers.js`,
> `admin-portal/src/hooks/useUserDetail.js`,
> `admin-portal/src/pages/Users.jsx`,
> `admin-portal/src/components/users/UserRow.jsx`,
> `admin-portal/src/components/users/UserDetailModal.jsx`,
> `supabase/migrations/20260813000000_admin_suspension_enforcement.sql`,
> and `admin-portal/supabase/admin_policies.sql`.

---

## Quick Facts

- **Suspension = hard ban.** `profiles.suspended` (boolean, base schema) flips
  the account off. A suspended user cannot sign in, cannot place orders, cannot
  message sellers, cannot use POS — and a suspended **admin loses console
  access immediately**.
- **Three enforcement layers** (defense in depth):
  1. **Flutter app** — `AuthGate` shows a "Account Suspended" screen and blocks
     the UI (login-layer ban).
  2. **Admin portal** — `useAuth` signs a suspended admin out and refuses
     sign-in.
  3. **Supabase RLS** — the server-side data-plane ban for already-authed
     sessions (writes + all elevated reads).
- **Only admins can suspend/reactivate** — through the admin portal Users page
  (or a direct DB update).
- **Audit trail:** `suspended_reason` + `suspended_at` are set by the portal on
  suspend and cleared on reactivate.
- **Guard rails (DB-enforced):** an admin cannot demote or suspend **their own
  account**, and the **last active admin** can never be demoted or suspended.
- **Migration `20260813000000_admin_suspension_enforcement.sql`** — applied to
  the live project (`psczvbfoybqhjeqssimw`) on **2026-08-12**. Deployment order
  matters: apply it **before** deploying the portal changes (see below).

---

## Enforcement layers

### 1. Database (RLS) — `supabase/migrations/20260813000000_admin_suspension_enforcement.sql`

| Piece | What it does |
|-------|--------------|
| `profiles.suspended_reason`, `suspended_at` | Audit columns (`suspended` already existed in the base schema) |
| `public.is_suspended()` | SECURITY DEFINER helper reading `profiles.suspended` for `auth.uid()`; policies call it **without re-entering profiles RLS** (avoids 42P17 infinite recursion) |
| Redefined `is_admin()` / `is_seller_or_admin()` | Both now add `AND NOT COALESCE(suspended, false)` — because nearly every admin/seller policy routes through these two helpers, a banned admin/seller loses **all** elevated access the instant the flag flips (no per-table policy edits) |
| Explicit `AND NOT public.is_suspended()` on customer-write policies | `orders`, `cart_items`, `reviews`, `product_reviews` (guarded — see gotcha #2), `customization_requests`, `conversations`, `messages`, `store_follows`, `sales_transactions` |
| Guard triggers `prevent_admin_self_lockout` / `protect_last_admin` | Reject UPDATEs that demote/suspend yourself, or that would leave zero active admins |

The migration is idempotent (`ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE`,
`DROP ... IF EXISTS`) — safe to re-run.

### 2. Flutter app — `lib/screens/auth_gate.dart`

- `_routeByRole(profile)` checks `profile['suspended'] == true` **before** any
  role routing and returns `_SuspendedAccountScreen`.
- The screen explains the ban, shows `suspended_reason` (if present) in a card,
  and offers **Sign out**. The session is only cleared when the user taps the
  button — the user stays on the screen rather than silently flipping to login.
- Why this must exist: **auth happens before any RLS policy runs**, so banning
  cannot be enforced at the login layer by the database alone.

### 3. Admin portal — `admin-portal/src/hooks/useAuth.jsx`

- `isBlocked(profile)` = `role !== 'admin' || suspended === true`.
- On session restore and on `signIn`, a blocked profile is signed out, sets
  `accessDenied`, and (on sign-in) throws
  `'Your admin account has been suspended.'`.

---

## Admin portal UI

### Users page (`Users.jsx` + `UserRow.jsx` + `UserDetailModal.jsx`)

- **Row level:** suspended rows get a red-tinted background + a "Suspended"
  pill next to the name.
- **Filters:** status chips **All / Active / Suspended** (client-side filter on
  `suspended`).
- **Detail modal tabs:**
  - **Account** — member since, ID, phone, seller status, suspension banner
    (reason + date), and **Admin Actions**: *Change role* and
    *Suspend account / Reactivate account* (reason textarea on suspend).
  - **Orders** (customers only) — `useUserOrders(userId)`: full order history
    with store name, item count, payment method, status badge, total.
  - **Business** (sellers only) — `useSellerPortfolio(userId)`: owned stores
    (open/closed/deactivated), KPI grid (online orders/revenue, POS
    sales/revenue, products, total revenue), and product listings (thumbnail,
    stock, hidden badge, price).
- **Role change modal** warns that the DB refuses to demote the last active
  admin or to change your own role.

### Hooks

| Hook | Purpose |
|------|---------|
| `useUsers()` | `profiles` grouped by role; `PROFILE_FIELDS` includes `suspended, suspended_reason, suspended_at` |
| `useUpdateUserStatus()` | Suspend (sets flag + reason + `suspended_at`) / reactivate (clears all three); invalidates users/applications/dashboard keys |
| `useUpdateUserRole()` | Sets `role` (customer/seller/admin); same invalidation |
| `useUserOrders(userId)` | Customer order history (Orders tab) |
| `useSellerPortfolio(sellerId)` | Seller stores + KPIs + product listings (Business tab) |

---

## Key file map

| Layer | File | Responsibility |
|-------|------|----------------|
| Flutter routing | `lib/screens/auth_gate.dart` | Suspended check → `_SuspendedAccountScreen` |
| Portal auth | `admin-portal/src/hooks/useAuth.jsx` | Block suspended admins (sign-out + accessDenied) |
| Portal list | `admin-portal/src/pages/Users.jsx` | Role tabs, Active/Suspended filters |
| Portal row | `admin-portal/src/components/users/UserRow.jsx` | Suspended pill + row tint |
| Portal modal | `admin-portal/src/components/users/UserDetailModal.jsx` | Account/Orders/Business tabs + suspend/role actions |
| Portal data | `admin-portal/src/hooks/useUsers.js` | Suspension columns + status/role mutations |
| Portal data | `admin-portal/src/hooks/useUserDetail.js` | Orders + seller portfolio queries |
| DB | `supabase/migrations/20260813000000_admin_suspension_enforcement.sql` | Columns, `is_suspended()`, redefined helpers, policy blocks, guard triggers |
| DB (portal) | `admin-portal/supabase/admin_policies.sql` | Mirrors the redefined `is_admin()` (must stay in sync) |

---

## Deploy order & status

1. **Apply the migration first** — the portal's `useUsers.js` selects
   `suspended_reason` / `suspended_at`; PostgREST 400s on missing columns until
   it has run (this was the original failure mode fixed on 2026-08-12).
2. **Deploy the portal** — the modal/hooks work once the columns exist.
3. **Ship a new app release** — the Flutter AuthGate block only lands with the
   next APK.
4. Status: migration **applied to the live DB** (verified 2026-08-12); release
   **v1.0.8** carries the Flutter-side block.

---

## Edge cases & gotchas

1. **Login-layer ban is app code, not SQL.** RLS cannot stop sign-in (auth runs
   before policies); the AuthGate / `useAuth` checks are the first line and RLS
   is the second.
2. **`product_reviews` may not exist** (legacy table, superseded by `reviews`).
   The migration guards that policy block with
   `to_regclass('public.product_reviews') IS NOT NULL`. Do **not** create the
   table "for completeness" — `20260717_product_reviews.sql` would overwrite the
   live `refresh_product_rating()` and break product ratings.
3. **Self-lockout / last-admin guards** surface as DB errors in the portal
   (e.g. "You cannot demote or suspend your own admin account.") — that is
   expected behavior, not a bug.
4. **CLI migration tracking is unreliable** (out-of-sync remote records). Verify
   what's applied via `supabase/MIGRATIONS_LIVE_STATUS.md`, not
   `supabase migration list`.
5. **Reactivating** clears `suspended_reason`/`suspended_at` back to NULL
   (the portal sends nulls) — the user regains access immediately, RLS-wise.
6. **Admin policies must stay in sync** — if `admin_policies.sql` is re-applied
   by hand, it must keep the `NOT COALESCE(suspended, false)` body or it will
   silently downgrade the ban for admins.
