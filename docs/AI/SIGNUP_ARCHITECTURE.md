# SoleVision — Sign Up Architecture (Split, Premium, Tiered Verification)

> Condensed reference for AI agents working on authentication / registration.
> Derived from the live codebase: `lib/screens/auth/account_entry_screen.dart`,
> `lib/screens/auth/customer_register_screen.dart`,
> `lib/screens/auth/seller_application_flow.dart`,
> `lib/providers/seller_application_controller.dart`,
> `lib/providers/auth_provider.dart`, `lib/services/auth_service.dart`,
> `lib/services/verification_document_service.dart`,
> `lib/screens/auth_gate.dart`, `lib/screens/auth/pending_approval_screen.dart`,
> `lib/screens/admin/seller_approval_screen.dart`, and
> `supabase/migrations/20260812000000_add_seller_tiered_verification.sql`.
>
> **Where do I start?** `account_entry_screen.dart` for the entry split,
> `seller_application_flow.dart` + `seller_application_controller.dart` for
> the seller flow, `auth_service.dart` for Supabase calls, and
> `auth_gate.dart` for post-signup routing.

---

## Quick Facts

- **The legacy single-form `RegisterScreen` (with the "Apply as a seller"
  toggle) is GONE.** Registration starts at the merged **AccountEntryScreen**
  (`lib/screens/auth/account_entry_screen.dart`) — a full-bleed video front
  door with an in-place `create` / `signin` mode switch. Its **create** mode
  splits into a slimmed **customer** flow and a 4-step **seller application
  flow**; its **signin** mode carries the login contract documented in
  `docs/AI/SIGN_IN_ARCHITECTURE.md`.
- **Stack:** Flutter + Supabase (Auth + Postgres `profiles` table +
  private Storage bucket `seller-verification-docs`).
- **State management:** ChangeNotifier + Provider (`AuthProvider` for
  auth; a scoped `SellerApplicationController` for the seller flow's
  form/upload state).
- **Roles:** `customer`, `seller`, `admin` — stored in `profiles.role`.
- **Seller gating:** `profiles.seller_status` ∈ `none`, `pending`,
  `approved`, `rejected`. The role flip `customer → seller` happens ONLY on
  admin approval (unchanged from legacy).
- **Tiered verification:** Tier 1 (ID, selfie, CUFMAI/barangay proof,
  store basics) is REQUIRED to apply. Tier 2 (DTI/BIR/permit via
  `seller_business_docs`) is OPTIONAL, post-approval, and never gates
  selling.
- **Auto-login after sign up** — customers land in `CustomerShell`;
  pending sellers land in `PendingApprovalScreen`.
- ⛔ **Temporary dev mode exists** (swipe ↑↑↓↓→→←← on the entry screen) —
  a signup skip that shows a "DEV MODE" chip. Mostly UI-only (no backend
  writes), with ONE exception: the seller flow's final Submit creates a
  REAL, PENDING seller application (same `signUpSeller` path as production)
  so the dev lands on PendingApprovalScreen and can test the full admin
  loop — approve → in-app notification + **Gmail approval email**.
  **REMOVE BEFORE RELEASE** — see `docs/AI/DEV_MODE_ARCHITECTURE.md` for
  the full removal checklist.

---

## Architecture Layers

```
PRESENTATION  AccountEntryScreen (create|signin modes) /
              CustomerRegisterScreen /
              SellerApplicationFlow / PendingApprovalScreen
STATE         AuthProvider  +  SellerApplicationController (scoped)
SERVICE       AuthService  +  VerificationDocumentService
BACKEND       Supabase Auth + profiles (RLS) + seller_business_docs (RLS)
              + storage bucket seller-verification-docs (PRIVATE)
```

---

## Entry & routing diagram

```
AccountEntryScreen (create mode, full-bleed video)
        │  "Shop as customer?"         "Apply to sell"
        ├──────────────────────────────┬───────────────────────────►
        ▼                              ▼
   CustomerRegisterScreen               SellerApplicationFlow (4 steps)
   (name/email/birthday/gender/         Account → Identity → Community → Storefront
    phone/password/terms)                         │
              │                                  AuthProvider.signUpSeller(data)
   AuthProvider.signUpCustomer()                 seller_status = 'pending'
   seller_status = 'none'                        │
              │                                  ▼
              ▼                            PendingApprovalScreen
   FootProfileOnboardingScreen            (shows submitted Tier 1 items,
   (AR scan / manual / skip)               explains optional Tier 2)
   NEVER a hard gate — all paths │
   land in the shell            ▼
                          CustomerShell

PendingApprovalScreen ──admin approve──▶ SellerApprovedCelebrationScreen
                                        (ONE-TIME welcome, persisted per user;
                                         "Go to dashboard →" → SellerShell)
PendingApprovalScreen ──admin reject──▶ CustomerShell + rejection banner
                                        (rejection_reason + "Re-apply" → flow)
```

**On approve/reject the applicant is emailed too** (not just the in-app
`approval` notification from the DB trigger `trg_notify_on_seller_approved`):
both admin surfaces (Flutter `OrderProvider.approveSeller/rejectSeller` and
admin-portal `useApproveApplication/useRejectApplication`) fire-and-forget
invoke the `send-approval-email` edge function (`supabase/functions/
send-approval-email/index.ts`) after the `profiles` update succeeds. It looks
up the applicant's `profiles.email` with the service role and sends via
Gmail SMTP (smtp.gmail.com:465, implicit TLS) using the app's own Gmail
account + App Password (env secrets `GMAIL_SENDER`, `GMAIL_APP_PASSWORD`).
No third-party email provider, no domain ownership, no DNS records — just
a dedicated Gmail. A failed email never fails the approval/rejection — the
DB update is the source of truth; the email is best-effort.

AuthGate's StreamBuilder still owns all post-auth routing (`_routeByRole`),
unchanged in spirit: `pending` → `PendingApprovalScreen`, `seller` +
`approved` → **`SellerApprovedCelebrationScreen` on first launch** (a
one-time "You're now part of the CUFMAI family!" welcome with a
"Go to dashboard →" CTA — per-user "seen" flag persisted in
SharedPreferences under `seller_celebration_seen_v1`, so it never shows
twice; every later launch goes straight to `SellerShell`), admin →
`AdminShell`, else → `CustomerShell`.

---

## Customer signup (UC001)

1. AccountEntryScreen (create mode) → **Shop as customer?**.
2. `CustomerRegisterScreen` collects: full name, email, **birthday
   (required, 13+, date picker with a short why-we-ask line)**, **gender
   (optional: Woman / Man / Prefer not to say / Self-describe → free-text
   field)**, phone (optional), password (+ live strength meter), confirm,
   terms checkbox.
3. Duplicate-email check (`AuthService.emailExists`) runs BEFORE creating
   the account and surfaces inline on the email field.
4. `AuthProvider.signUpCustomer(...)` → `AuthService.signUp(...)` creates
   the Supabase user and upserts `profiles` (role `customer`,
   `seller_status: 'none'`, `birthday`, `gender`) → auto-login.
5. The register screen then `pushReplacement`s to
   **`FootProfileOnboardingScreen`** (customer flow ONLY — sellers never see
   it). **Account creation already succeeded at this point**; onboarding is
   a separate, always-skippable step and never blocks access.
6. Onboarding completion pops to the first route, where AuthGate has
   already swapped the root to **CustomerShell**.

---

## Customer foot-profile onboarding (post-signup step)

`lib/screens/auth/foot_profile_onboarding_screen.dart` — shown ONCE,
immediately after signup, to introduce the AR foot scanner. Three paths,
deliberately unequal in visual weight:

| Path | Visual | Persists to profiles |
|------|--------|----------------------|
| **Scan with AR** (primary) | accent-filled card, larger, "RECOMMENDED" badge | `foot_profile_source = 'ar_scan'` — stamped by `FootResultsScreen` after the scan saves (full fidelity → `foot_measurements`) |
| **Manual entry** (secondary) | outline card, inline EU size + width pickers | `foot_profile_source = 'manual'` + `foot_size_ph` + `foot_width` |
| **Skip for now** (tertiary) | plain text button | `foot_profile_source = 'skipped'` (best-effort — never blocks) |

- The AR path pushes the EXISTING `FootInstructionsScreen` (the pre-existing
  scan flow) **on top of** the onboarding screen — so an abandoned scan,
  camera-permission denial or AR failure lands the user back on onboarding
  with the manual option in plain sight. Never a dead end.
- Persistence goes through `AuthProvider.saveFootProfile(...)`
  (`SupabaseService.updateProfileFootSnapshot`), which refreshes
  `_profile` so watchers update immediately.
- `FootResultsScreen._saveToProfile` also stamps the snapshot on EVERY scan
  (profile-tab re-scans included): live AR → `'ar_scan'`, paper camera scan
  → `'manual'` (the scan's `paperSize` decides).

### Reminder banner (skipped / never-touched profiles)

`lib/widgets/customer_foot_profile_banner.dart` — a quiet, dismissible card
on the HOME screen (one placement, never a pop-up) shown when
`profiles.foot_profile_source` is `NULL` (pre-feature accounts) or
`'skipped'` (`AppConstants.needsFootProfile`). Dismiss hides it for the
SESSION only (in-memory, per account) — "skip" never means "never ask again
silently". The banner's **Complete** button reopens the same AR scan flow;
it disappears for good once the profile snapshot is written.

---

## Seller application flow (the important part)

**Five steps** in `SellerApplicationFlow` (stepper in
`StepProgressIndicator`):

| Step | Fields | Validation gate |
|------|--------|-----------------|
| 1 · Account | full name, email, phone (required), **birthday** (required, 13+, `profiles.birthday`), **gender** (optional chips + self-describe, `profiles.gender`), password, confirm, terms | form + duplicate-email check at Continue |
| 2 · Identity | **government ID type** (picker of `AppConstants.govIdTypes` — stored as `profiles.id_type`), government ID photo, liveness selfie | type + both photos picked |
| 3 · Community | segmented: CUFMAI member ID (optional field) **or** barangay proof upload; **store location** (pushed `StoreLocationPickerScreen` — a lightweight full-screen map pin + MapTiler geocoding/GPS picker, no delivery-address form → `profiles.store_location` + `store_lat`/`store_lng`) | member/barangay + location |
| 4 · Business | **DTI certificate**, **BIR COR**, **mayor's/barangay permit** — all three REQUIRED, uploaded to the private verification bucket and written to `seller_business_docs` (status `pending`) | all 3 docs uploaded |
| 5 · Storefront | store name, store description **(optional** — can be added later via Create/Edit Store → `stores.description`), **store tags** (store-specific preset vocabulary — Craft & heritage / Local pride / Services & offers — via `TagSelector(groups: storeTagGroups)` → `profiles.store_tags`, copied to `stores.tags` at store creation), **store-front photo** (public `store-assets` bucket — doubles as the store banner), **5 product photos** (private verification bucket) | form + at least 1 tag + store-front + all 5 product photos |

**State** lives in `SellerApplicationController` (a ChangeNotifier scoped
to the flow route via `ChangeNotifierProvider.value`), so navigating
between steps — or leaving and re-entering the flow in the same session —
never loses entered data. Documents are held as local file paths until
submit.

### When is the Supabase Auth user created? — only at final submit

The spec's key edge case is "user abandons the flow after Step 1". This
flow **never creates the auth user (or profile) until Step 4's submit**, so
abandonment cannot leave orphaned accounts. The final `submit()` sequence
is:

1. `AuthService.ensureUser(...)` — creates the account (or reuses the
   existing session when re-applying; a `signUp` that returns no session
   because the account already exists falls back to `signInWithPassword`).
2. Upload pending documents to the PRIVATE bucket via
   `VerificationDocumentService.uploadDocument` (deterministic paths
   `{userId}/{docKey}.jpg`, upsert). Per-doc status drives the animated
   submission checklist; each doc has a designed error + retry.
3. `AuthService.completeSellerApplication(...)` upserts the profile with
   all Tier 1 fields and `seller_status: 'pending'` (`role` stays
   `customer`).
4. `AuthProvider.signUpSeller(...)` caches the session → AuthGate routes to
   **PendingApprovalScreen**.

The whole sequence is **idempotent**: retrying skips already-uploaded docs,
`ensureUser` reuses the matching session, and the profile upsert overwrites
cleanly. If submit fails mid-way, a designed error card with **Try again**
keeps the submission checklist visible (never a bare SnackBar).

### Re-apply (rejected sellers)

Rejected sellers land in `CustomerShell`; the Profile screen shows a banner
with `rejection_reason` (if present) and a **Re-apply as a seller** button
that opens `SellerApplicationFlow(prefillProfile: profile)`. The flow
detects `seller_status == 'rejected'` and skips the password step (the
existing session is reused; `ensureUser` requires a password only when no
session exists).

---

## PendingApprovalScreen (redesigned)

`lib/screens/auth/pending_approval_screen.dart` (moved out of
`auth_gate.dart`):
- Shows **which Tier 1 items were submitted** ("What we received" card with
  per-item checkmarks driven by the profile's new columns).
- Explains **Tier 2 is optional** and only available after approval.
- Keeps the **Log out** action.

---

## Tier 2 — Business Verification (optional, decoupled)

- `profiles` is untouched by Tier 2; documents live in the
  `seller_business_docs` table (one row per profile,
  `verification_status` ∈ `none | pending | verified | rejected`).
- `SellerBusinessVerificationScreen` (seller, post-approval): three upload
  tiles (DTI cert, BIR COR, mayor's/barangay permit) that upload
  immediately on pick, then **Submit for verification** →
  `AuthService.submitBusinessVerification(...)` sets status `pending`.
- **Owners can never self-certify**: the DB trigger
  `guard_seller_business_docs_status` blocks any owner write of `verified`
  (or `rejected`); admins set verdicts through the SECURITY DEFINER RPC
  `set_business_verification_status(uuid, text)` (re-checks `is_admin()`).
- Admin review list: `SellerApprovalScreen` now has a two-tab segmented
  control — **Applications** (Tier 1 queue) and **Business Docs**
  (`SellerBusinessDocsReviewScreen`, Tier 2 queue with Verify/Reject).
- Entry point for sellers: Profile → Settings → **Business Verification**
  (with a live status pill).

---

## Backend — data model & RLS

`supabase/migrations/20260812000000_add_seller_tiered_verification.sql`:

**`profiles` (all additive, nullable → legacy users unaffected):**
`id_document_url`, `selfie_url`, `cufmai_member_id`, `barangay_proof_url`,
`store_front_url` (PUBLIC `store-assets` path — reused as the store banner
by `StoreService.createStore`), `product_photo_urls` (private `TEXT[]`,
all 5 required), `store_name`, `store_description`. (The former `payout_method` /
`payout_details` columns still exist but are no longer written — payout
setup is out of scope for the application flow.)

**`seller_business_docs`:** `profile_id` (FK, unique), `dti_cert_url`,
`bir_cor_url`, `permit_url`, `verification_status`, `submitted_at`,
`verified_at`, `created_at`. RLS: owner SELECT/INSERT/UPDATE own row;
admin SELECT/UPDATE all; owner status guard trigger; admin RPC verdict.

**Storage bucket `seller-verification-docs` (PRIVATE):** policies key off
the first path segment `{userId}` — owners can INSERT/SELECT/UPDATE/DELETE
their own folder, admins can SELECT all, anon gets nothing. Document
viewing uses `createSignedUrl` (RLS applies to signed-URL creation), never
a public URL.

### Profile fallback (unchanged)

`AuthService.getProfile` still retries (×5) for the auth trigger, then
manually upserts a minimal profile as a safety net.

---

## Key file map

| Layer | File | Responsibility |
|-------|------|----------------|
| Entry | `lib/screens/auth/account_entry_screen.dart` | Merged front door (create = role split, signin = login) |
| UI | `lib/screens/auth/customer_register_screen.dart` | Customer signup (name, email, birthday 13+, optional gender, phone, password, terms) |
| UI | `lib/screens/auth/foot_profile_onboarding_screen.dart` | Post-signup foot-profile step: AR scan / manual / skip (never a hard gate) |
| Widget | `lib/widgets/customer_foot_profile_banner.dart` | Dismissible home-screen reminder for skipped/incomplete foot profiles |
| Utils | `lib/utils/customer_profile_fields.dart` | Birthday/gender validation, EU size + width lists, `formatBirthdayForDb` |
| UI | `lib/screens/auth/seller_application_flow.dart` | 4-step seller application + submission checklist |
| State | `lib/providers/seller_application_controller.dart` | Seller form + upload + submit orchestration |
| UI | `lib/screens/auth/pending_approval_screen.dart` | Post-apply locked screen (Tier 1 summary + Tier 2 explainer) |
| UI | `lib/screens/seller/seller_business_verification_screen.dart` | Tier 2 upload/submit (seller, post-approval) |
| State | `lib/providers/auth_provider.dart` | `signUpCustomer()` / `signUpSeller()` |
| Service | `lib/services/auth_service.dart` | signUp, ensureUser, completeSellerApplication, Tier 2 methods, admin verdict RPC |
| Service | `lib/services/verification_document_service.dart` | Private-bucket uploads + signed URLs |
| Routing | `lib/screens/auth_gate.dart` | Role-based routing (unchanged) |
| Admin UI | `lib/screens/admin/seller_approval_screen.dart` | Tier 1 queue + Business Docs tab |
| Shared UI | `lib/widgets/auth/` | `SignupScaffold`, `AuthTextField`, `PasswordStrengthMeter`, `DocumentUploadTile`, `StepProgressIndicator` |
| Schema | `supabase/migrations/20260812000000_add_seller_tiered_verification.sql` | Tier 1 columns + Tier 2 table + private bucket + RLS |

---

## Edge cases & gotchas

1. **No orphaned accounts**: auth user + profile are created only at the
   final submit of the seller flow.
2. **Legacy approved sellers / customers** have NULL Tier 1 fields — that's
   acceptable everywhere (`AuthGate`, `SellerShell`, profile). Never treat
   missing Tier 1 data as an error state.
3. **Duplicate email** surfaces at Step 1 (inline) and again authoritatively
   at `auth.signUp` (final submit) — a duplicate that slipped through shows
   a designed error in the submission checklist.
4. **Upload failure mid-submit**: docs keep their per-doc error state with
   retry; already-uploaded docs are skipped on re-run.
5. **Rejected sellers**: land in CustomerShell with `rejection_reason`
   surfaced on the Profile banner + a re-apply entry that prefills their
   data.
6. **`AnimatedSwitcher` + GlobalKeys**: each seller-flow step has its OWN
   Form GlobalKey (`_accountFormKey`, `_storefrontFormKey`, …) — sharing a
   key between steps would crash with "Duplicate GlobalKey" during the
   transition.
7. **Document viewer**: private docs are opened via short-lived signed URLs
   (admin review zoom uses `InteractiveViewer`).
8. **Re-apply without a live session** throws a clear "sign in again"
   message (`ensureUser` requires password/fullName when no session).
9. **Customer onboarding is NOT a hard gate**: account creation completes
   BEFORE `FootProfileOnboardingScreen` exists; all three paths (and even
   the Android back button) land in `CustomerShell`. `pushReplacement` (not
   push) swaps the register screen for onboarding so the stack stays clean.
10. **`foot_profile_source` semantics**: `'ar_scan'` (live AR tap-to-
    measure) > `'manual'` (manual size picker OR paper camera scan) >
    `'skipped'`/NULL (reminder banner shows). Full scan fidelity always
    lives in `foot_measurements`; `profiles.foot_size_ph` is the cheap
    snapshot (effective EU size as a number), `foot_width` is only set by
    the manual picker. See migration `20260812130000_add_customer_profile_fields.sql`.
11. **Birthday is sent as local YYYY-MM-DD** (`formatBirthdayForDb`) so the
    DATE column never shifts across midnight via UTC serialization.
