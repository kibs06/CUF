# SoleVision — Sign Up & Seller Application Architecture

**Last Updated:** August 12, 2026
**Purpose:** Comprehensive documentation of the account registration flow for both Customers and Sellers in SoleVision — an artisan leather footwear e-commerce app built with Flutter + Supabase.

---

## Quick Summary

SoleVision uses a **single, unified registration screen** that serves both Customer and Seller sign-up. A toggle switch ("Apply as a seller") determines which lifecycle a new account enters:

- **Customer:** Account is created and usable immediately.
- **Seller applicant:** Account is created with a `pending` seller status, gated behind an admin review screen until an admin approves it.

All sign-up logic follows the layered pattern: `Screen → Provider → Service → Supabase`.

---

## Table of Contents

1. [Roles & Status Model](#1-roles--status-model)
2. [Registration UI](#2-registration-ui)
3. [Data Flow Architecture](#3-data-flow-architecture)
4. [Customer Sign-Up Flow](#4-customer-sign-up-flow)
5. [Seller Sign-Up Flow (Application)](#5-seller-sign-up-flow-application)
6. [Admin Approval Workflow](#6-admin-approval-workflow)
7. [Post-Registration Routing (AuthGate)](#7-post-registration-routing-authgate)
8. [Backend Schema & Security](#8-backend-schema--security)
9. [Key Files](#9-key-files)
10. [Edge Cases & Error Handling](#10-edge-cases--error-handling)

---

## 1. Roles & Status Model

The `profiles` table drives all authorization decisions after authentication.

| Field | Allowed Values | Default | Meaning |
|-------|---------------|---------|---------|
| `role` | `customer`, `seller`, `admin` | `customer` | Primary account capability |
| `seller_status` | `none`, `pending`, `approved`, `rejected` | `pending` | Seller lifecycle stage |

**Important:** Sign-up **always** writes `role = 'customer'`. A user only becomes `seller` after an admin approves the application, which flips `role` to `seller` and `seller_status` to `approved`.

| seller_status | Meaning |
|--------------|---------|
| `none` | Regular customer — never applied to sell. |
| `pending` | Applied as seller — waits for admin review. |
| `approved` | Admin approved — full seller dashboard + POS access. |
| `rejected` | Admin rejected — remains a functional customer account. |

---

## 2. Registration UI

**File:** `lib/screens/auth/register_screen.dart`

The screen is a `Form` inside a `SoleCard` with the following fields:

| Field | Widget | Validation |
|-------|--------|-----------|
| Full Name | `SoleTextField` | Required, non-empty |
| Email Address | `SoleTextField` (email keyboard) | Required, must contain `@` |
| Password | `SoleTextField` (obscured) | Min 6 characters |
| Confirm Password | `SoleTextField` (obscured) | Must equal Password |
| Apply as a seller | `SwitchListTile` | Optional |

When the seller switch is ON, an amber info chip appears:

> "Your application will be reviewed by an admin before approval."

**Submit button:** `SolePrimaryButton` labelled *Register* — shows a loading spinner (`_isSubmitting || auth.isLoading`), blocks double-submission, and reports failures via SnackBar.

---

## 3. Data Flow Architecture

```
PRESENTATION  RegisterScreen          (lib/screens/auth/register_screen.dart)
STATE         AuthProvider            (lib/providers/auth_provider.dart)
SERVICE       AuthService             (lib/services/auth_service.dart)
BACKEND       Supabase (Auth + profiles table, RLS-protected)
```

```
RegisterScreen._submit()
   │  Form validate → guard against double submit
   ▼
AuthProvider.signUp(fullName, email, password, applyAsSeller)
   │  sellerStatus = applyAsSeller ? 'pending' : 'none'
   ▼
AuthService.signUp(...)               1. supabase.auth.signUp(email, password,
   │                                     data: {full_name})
   │                                 2. upsert profiles row (id, full_name, email,
   │                                     role='customer', seller_status, avatar_url=null, phone=null)
   │                                 3. getProfile(user.id) — retry ×5; manual
   │                                     upsert fallback if trigger is slow
   ▼
AuthProvider caches {user, profile} → onLoginHook → FollowProvider.loadForUser()
   ▼
Success SnackBar → Navigator.pop()
   │
   ▼
AuthGate listens to authStateChanges → routes by role (Section 7)
```

---

## 4. Customer Sign-Up Flow

**Trigger:** Register screen with *Apply as a seller* = **OFF**.

1. **UI submission** — `_submit()` validates all fields, then calls
   `AuthProvider.signUp(..., applyAsSeller: false)`.
2. **Provider** — `AuthProvider.signUp` (`lib/providers/auth_provider.dart:89`) sets
   `sellerStatus = 'none'` and calls `AuthService.signUp`.
3. **Service** — `AuthService.signUp` (`lib/services/auth_service.dart:79`):
   - Creates the Supabase Auth user with user metadata `{full_name}`.
   - Upserts a `profiles` row:
     ```
     id = user.id, full_name, email, role = 'customer',
     seller_status = 'none', avatar_url = null, phone = null
     ```
   - Fetches the profile back (with retry/fallback).
4. **Auto-login** — the provider stores `_currentUser` and `_profile`, fires the
   login hook, and returns `true`.
5. **UI feedback** — SnackBar *"Welcome to CUFMAI!"* (green), then `Navigator.pop()`.
6. **Routing** — `AuthGate` detects the signed-in session, loads the profile, and
   routes the user into the **CustomerShell** (4-tab customer experience).

**Result:** The customer can immediately browse, cart, and order — no activation step.

---

## 5. Seller Sign-Up Flow (Application)

**Trigger:** Register screen with *Apply as a seller* = **ON**.

Steps 1–4 are identical to the customer flow, **except**:

- `AuthProvider.signUp` passes `sellerStatus = 'pending'`.
- The profile row is written with `role = 'customer'` **and** `seller_status = 'pending'`.
- The success SnackBar reads *"Account created! Application sent to Admins."*

**Routing difference (step 6):** `AuthGate._routeByRole` checks status before role:

```
role == 'admin'                    → AdminShell
role == 'seller' && approved       → SellerShell
seller_status == 'pending'         → PendingApprovalScreen   ← seller applicant lands here
else                               → CustomerShell
```

### PendingApprovalScreen

**File:** `lib/screens/auth_gate.dart:245` — a full-screen lock visible to seller applicants:

- Hourglass icon with amber `statusPendingColor` tint
- Title: **"Seller Application Pending"**
- Body: *"Your account was created. An admin needs to approve your seller access
  before you can open the seller dashboard."*
- Log Out button — the only action available.

The applicant **cannot** access the SellerShell, upload products, or operate POS
until approved.

---

## 6. Admin Approval Workflow

1. **Listing pending applications** — `AuthService.fetchPendingSellerApplications()`
   (`auth_service.dart:112`) queries:
   ```sql
   SELECT * FROM profiles
   WHERE seller_status = 'pending'
   ORDER BY created_at DESC
   ```
   Served by `SellerApprovalScreen` (`lib/screens/admin/seller_approval_screen.dart`),
   which loads profiles via `OrderProvider.loadProfiles()`.

2. **Approve** — `AuthService.approveSeller(userId)` (`auth_service.dart:121`):
   ```sql
   UPDATE profiles SET role = 'seller', seller_status = 'approved'
   WHERE id = userId
   ```
   Confirmation dialog: *"Authorize 'name' to upload products and execute register POS sales?"*

3. **Reject** — `AuthService.rejectSeller(userId)` (`auth_service.dart:131`):
   ```sql
   UPDATE profiles SET seller_status = 'rejected' WHERE id = userId
   ```
   The applicant keeps `role = 'customer'` and loses the seller lock.

4. **Customer-visible effect** — there is no real-time push; the change takes effect
   on the next profile load (app restart or re-login). An approved seller then routes
   to **SellerShell**; a rejected one routes to **CustomerShell**.

---

## 7. Post-Registration Routing (AuthGate)

**File:** `lib/screens/auth_gate.dart`

`AuthGate` is the root-level `StreamBuilder<AuthState>` on `authStateChanges`:

- **No session** → `_FirstTimeOrLoginRouter`: onboarding (first launch, checked via
  SharedPreferences `has_seen_onboarding`) or LoginScreen.
- **Session, profile loading** → loading screen, then `_routeByRole(profile)`.
- **Profile fetch fails** → connectivity-aware error view with retry
  (`TimeoutException` / `PostgrestException` are mapped to friendly copy).

**Role routing logic** (`_routeByRole`, `auth_gate.dart:174`):

| Condition | Destination |
|-----------|-------------|
| `role == 'admin'` | `AdminShell` |
| `role == 'seller' && seller_status == 'approved'` | `SellerShell` |
| `seller_status == 'pending'` | `PendingApprovalScreen` |
| anything else (customer / rejected) | `CustomerShell` |

Login/signup hooks fire `FollowProvider.loadForUser(userId)`; logout resets it.

---

## 8. Backend Schema & Security

### profiles table

**Migration:** `supabase/migrations/20260601000000_base_schema.sql:37`

```sql
CREATE TABLE IF NOT EXISTS public.profiles (
    id               UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name        TEXT NOT NULL,
    email            TEXT NOT NULL UNIQUE,
    phone            TEXT,
    role             TEXT NOT NULL DEFAULT 'customer'
                         CHECK (role IN ('customer', 'seller', 'admin')),
    seller_status    TEXT NOT NULL DEFAULT 'pending'
                         CHECK (seller_status IN ('none', 'pending', 'approved', 'rejected')),
    avatar_url       TEXT,
    suspended        BOOLEAN DEFAULT false,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);
```

### RLS Policies

| Operation | Policy |
|-----------|--------|
| SELECT | Public (`FOR SELECT USING (true)`) |
| INSERT | Owner only — `auth.uid() = id` |
| UPDATE | Owner only — `auth.uid() = id` **or** admin role |
| Admin read/update | Role-checked policies on all rows |

The DB trigger that normally auto-creates a profile on auth signup can lag; the
client compensates with a retry loop and manual upsert fallback
(`AuthService.getProfile`, `auth_service.dart:16`).

---

## 9. Key Files

| Layer | File | Responsibility |
|-------|------|----------------|
| UI | `lib/screens/auth/register_screen.dart` | Registration form, validation, seller toggle |
| UI | `lib/screens/auth/login_screen.dart` | Login screen; links to Register |
| State | `lib/providers/auth_provider.dart` | `signUp()`, `login()`, auto-login, hooks, error state |
| Service | `lib/services/auth_service.dart` | Supabase auth calls, profile upsert/get, seller approve/reject |
| Service | `lib/services/supabase_service.dart` | Profile CRUD used by provider |
| Routing | `lib/screens/auth_gate.dart` | Session stream, role router, `PendingApprovalScreen` |
| Admin UI | `lib/screens/admin/seller_approval_screen.dart` | Pending seller review + approve/reject |
| Constants | `lib/constants/app_constants.dart` | Role/status string constants (lines 215–227) |
| Schema | `supabase/migrations/20260601000000_base_schema.sql` | `profiles` table + RLS |

---

## 10. Edge Cases & Error Handling

1. **Duplicate email** — blocked by Supabase Auth and `profiles.email UNIQUE`;
   error surfaces in the red SnackBar.
2. **Profile write race** — trigger lag is handled by `getProfile`'s 5-attempt
   retry with exponential backoff, then a manual upsert fallback.
3. **Pending seller on customer shell** — impossible; `_routeByRole` checks
   `seller_status == 'pending'` before the customer fallback.
4. **Rejected seller** — remains `role = 'customer'`, keeps full customer access
   (routes to CustomerShell).
5. **Stale session on re-login** — `AuthService.signIn` force-signs-out any
   existing session first so account switches never inherit old state.
6. **Double-submit** — guarded by `_isSubmitting` local state plus `auth.isLoading`.
7. **No email verification gate** — sign-up auto-logs-in immediately; profile
   availability is guaranteed by the fallback upsert.
8. **Admin approval latency** — no push on role change; the seller sees the new
   shell after a profile reload (restart or re-login).

---

## Related Documentation

- `docs/AI/SIGNUP_ARCHITECTURE.md` — condensed AI-agent context version of this document.
- `docs/CUSTOMER_ARCHITECTURE.md` — customer module deep-dive.
- `docs/SELLER_MODULE_GUIDE.md` — seller module deep-dive.
- `docs/PROJECT_HANDOFF.md` — overall project orientation.