# SoleVision — Sign Up Architecture (Split, Premium, Tiered Verification)

> Condensed reference for AI agents working on authentication / registration.
> Derived from the live codebase: `lib/screens/auth/role_choice_screen.dart`,
> `lib/screens/auth/customer_register_screen.dart`,
> `lib/screens/auth/seller_application_flow.dart`,
> `lib/providers/seller_application_controller.dart`,
> `lib/providers/auth_provider.dart`, `lib/services/auth_service.dart`,
> `lib/services/verification_document_service.dart`,
> `lib/screens/auth_gate.dart`, `lib/screens/auth/pending_approval_screen.dart`,
> `lib/screens/admin/seller_approval_screen.dart`, and
> `supabase/migrations/20260812000000_add_seller_tiered_verification.sql`.
>
> **Where do I start?** `role_choice_screen.dart` for the entry split,
> `seller_application_flow.dart` + `seller_application_controller.dart` for
> the seller flow, `auth_service.dart` for Supabase calls, and
> `auth_gate.dart` for post-signup routing.

---

## Quick Facts

- **The legacy single-form `RegisterScreen` (with the "Apply as a seller"
  toggle) is GONE.** Registration now starts at a **RoleChoiceScreen** that
  splits into a slimmed **customer** flow and a 4-step **seller application
  flow**.
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
  store basics, payout) is REQUIRED to apply. Tier 2 (DTI/BIR/permit via
  `seller_business_docs`) is OPTIONAL, post-approval, and never gates
  selling.
- **Auto-login after sign up** — customers land in `CustomerShell`;
  pending sellers land in `PendingApprovalScreen`.

---

## Architecture Layers

```
PRESENTATION  RoleChoiceScreen / CustomerRegisterScreen /
              SellerApplicationFlow / PendingApprovalScreen
STATE         AuthProvider  +  SellerApplicationController (scoped)
SERVICE       AuthService  +  VerificationDocumentService
BACKEND       Supabase Auth + profiles (RLS) + seller_business_docs (RLS)
              + storage bucket seller-verification-docs (PRIVATE)
```

---

## Entry & routing diagram

```
LoginScreen ──"Register"──▶ RoleChoiceScreen
                                │
              ┌─────────────────┴──────────────────┐
              ▼                                    ▼
   CustomerRegisterScreen               SellerApplicationFlow (4 steps)
   (name/email/phone/password/terms)    Account → Identity → Community → Storefront
              │                                    │
   AuthProvider.signUpCustomer()       AuthProvider.signUpSeller(data)
   seller_status = 'none'              seller_status = 'pending'
              │                                    │
              ▼                                    ▼
        CustomerShell                     PendingApprovalScreen
                                         (shows submitted Tier 1 items,
                                          explains optional Tier 2)

PendingApprovalScreen ──admin approve──▶ SellerShell (role flipped to seller)
PendingApprovalScreen ──admin reject──▶ CustomerShell + rejection banner
                                        (rejection_reason + "Re-apply" → flow)
```

AuthGate's StreamBuilder still owns all post-auth routing (`_routeByRole`),
unchanged in spirit: `pending` → `PendingApprovalScreen`, `seller` +
`approved` → `SellerShell`, admin → `AdminShell`, else → `CustomerShell`.

---

## Customer signup (UC001)

1. RoleChoiceScreen → **Continue as customer**.
2. `CustomerRegisterScreen` collects: full name, email, phone (optional),
   password (+ live strength meter), confirm, terms checkbox.
3. Duplicate-email check (`AuthService.emailExists`) runs BEFORE creating
   the account and surfaces inline on the email field.
4. `AuthProvider.signUpCustomer(...)` → `AuthService.signUp(...)` creates
   the Supabase user, upserts `profiles` with `role: 'customer'`,
   `seller_status: 'none'` → auto-login → AuthGate → **CustomerShell**.

---

## Seller application flow (the important part)

**Four steps** in `SellerApplicationFlow` (stepper in
`StepProgressIndicator`):

| Step | Fields | Validation gate |
|------|--------|-----------------|
| 1 · Account | full name, email, phone (required), password, confirm, terms | form + duplicate-email check at Continue |
| 2 · Identity | government ID photo, liveness selfie | both picked |
| 3 · Community | segmented: CUFMAI member ID (optional field) **or** barangay proof upload | at least one |
| 4 · Storefront | store name, store description (20+ chars), payout method (GCash/Bank), payout details | form |

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
`store_name`, `store_description`, `payout_method` (check `gcash|bank`),
`payout_details`.

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
| Entry | `lib/screens/auth/role_choice_screen.dart` | Role split (customer vs seller) |
| UI | `lib/screens/auth/customer_register_screen.dart` | Slimmed customer signup |
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
