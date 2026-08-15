# 🔐 Auth & Accounts

> Everything about signup, login, roles, suspension, and profile management. **#moc**

---

## 📌 Overview

Three user roles (`customer`, `seller`, `admin`) live in `profiles.role`. The **role split starts at `RoleChoiceScreen`**: customers get a slim one-form signup, sellers get a **4-step application flow**. Auth is handled by Supabase Auth (email/password) with a **5-retry profile fetch** in `AuthService.getProfile` to survive the profile-trigger race. Post-auth routing is owned by `AuthGate`'s `StreamBuilder` (`_routeByRole`): pending sellers → `PendingApprovalScreen`, approved sellers → `SellerShell`, admins → `AdminShell`, everyone else → `CustomerShell`.

Account state is a hard on/off switch: **suspension** (`profiles.suspended`) is enforced in three layers — Flutter AuthGate, admin portal `useAuth`, and Supabase RLS.

---

## 🗺️ Entry & routing diagram

```
LoginScreen ──"Register"──▶ RoleChoiceScreen
                                │
              ┌─────────────────┴──────────────────┐
              ▼                                    ▼
   CustomerRegisterScreen               SellerApplicationFlow (4 steps)
   (name/email/birthday/gender/         Account → Identity → Community → Storefront
    phone/password/terms)                         │
              │                                  AuthProvider.signUpSeller(data)
   AuthProvider.signUpCustomer()                 seller_status = 'pending'
   seller_status = 'none'                        │
              │                                  ▼
              ▼                            PendingApprovalScreen
   FootProfileOnboardingScreen            (Tier 1 summary + Tier 2 explainer)
   (AR scan / manual / skip)
   NEVER a hard gate              ──admin approve──▶ SellerShell (role flipped)
              │                   ──admin reject───▶ CustomerShell + rejection banner
              ▼
          CustomerShell
```

---

## 🧩 Components

| Layer | File | Responsibility |
|-------|------|----------------|
| Entry | `lib/screens/auth/role_choice_screen.dart` | Role split (customer vs seller) |
| UI | `lib/screens/auth/customer_register_screen.dart` | Customer signup: name, email, **birthday (13+, required)**, gender (optional, self-describe), phone, password + strength meter, terms checkbox |
| UI | `lib/screens/auth/foot_profile_onboarding_screen.dart` | Post-signup foot-profile step — AR scan / manual / skip (never blocks) |
| Widget | `lib/widgets/customer_foot_profile_banner.dart` | Dismissible home-screen reminder when `foot_profile_source` is NULL/'skipped' |
| UI | `lib/screens/auth/seller_application_flow.dart` | 4-step seller application + animated submission checklist |
| State | `lib/providers/seller_application_controller.dart` | Scoped `ChangeNotifier` holding the seller form + doc uploads across steps |
| UI | `lib/screens/auth/pending_approval_screen.dart` | Post-apply locked screen |
| UI | `lib/screens/seller/seller_business_verification_screen.dart` | Tier 2 (optional) uploads: DTI / BIR COR / permit |
| State | `lib/providers/auth_provider.dart` | `signUpCustomer()` / `signUpSeller()`, profile cache |
| Service | `lib/services/auth_service.dart` | signUp, `ensureUser`, `completeSellerApplication`, Tier 2 + admin verdict RPCs, 5× profile retry |
| Service | `lib/services/verification_document_service.dart` | Private-bucket uploads + signed URLs |
| Routing | `lib/screens/auth_gate.dart` | Role routing + **suspended → `_SuspendedAccountScreen`** |
| Admin UI | `lib/screens/admin/seller_approval_screen.dart` | Tier 1 queue + Business Docs tab |
| Schema | `supabase/migrations/20260812000000_add_seller_tiered_verification.sql` | Tier 1 columns, `seller_business_docs`, private bucket, RLS |

---

## 📝 Seller application (the important part)

- **4 steps**: Account → Identity (gov ID photo + liveness selfie) → Community (CUFMAI member ID **or** barangay proof — at least one) → Storefront (store name, description 20+ chars, payout method GCash/Bank + details).
- **No orphaned accounts**: the Supabase auth user + profile are created **only at final submit** (Step 4). Abandoning mid-flow leaves nothing behind.
- Submit sequence: `ensureUser` (create or reuse session) → upload docs to **private** bucket `seller-verification-docs` (`{userId}/{docKey}.jpg`, upsert) → `completeSellerApplication` upserts profile with Tier 1 fields + `seller_status: 'pending'` (**role stays `customer`**) → AuthGate routes to PendingApproval.
- **Idempotent**: retries skip already-uploaded docs; failed docs keep per-doc error + retry (never a bare SnackBar).
- **Re-apply** (rejected sellers): Profile banner shows `rejection_reason` + "Re-apply as a seller" → `SellerApplicationFlow(prefillProfile:)`; skips the password step (session reused).

## 🦶 Foot-profile onboarding (customer, post-signup)

| Path | Persists |
|------|----------|
| Scan with AR (primary, "RECOMMENDED") | `foot_profile_source = 'ar_scan'` + full fidelity in `foot_measurements` |
| Manual entry (EU size + width) | `'manual'` + `foot_size_ph` + `foot_width` |
| Skip for now | `'skipped'` (best-effort, banner reappears next session) |

## 🏢 Tier 2 — Business verification (optional, never gates selling)

- Docs live in `seller_business_docs` (`verification_status` ∈ none/pending/verified/rejected). `profiles` untouched.
- Owners **can never self-certify**: trigger `guard_seller_business_docs_status` blocks owner writes of `verified`/`rejected`; admins set verdicts via SECURITY DEFINER RPC `set_business_verification_status(uuid, text)`.

## ⛔ Suspension (hard ban — 3 layers)

1. **Flutter**: `AuthGate._routeByRole` checks `suspended == true` **before** role routing → `_SuspendedAccountScreen` (shows reason, Sign out only). Auth runs before RLS, so this layer is required.
2. **Admin portal**: `useAuth.isBlocked` = `role !== 'admin' || suspended === true` → sign-out + `accessDenied`.
3. **RLS**: `is_suspended()` helper + redefined `is_admin()`/`is_seller_or_admin()` (`AND NOT COALESCE(suspended,false)`) — a banned account loses all elevated access instantly; customer-write policies get explicit `AND NOT is_suspended()`.

**Guard rails (DB-enforced)**: can't suspend/demote your own account; the **last active admin** can never be demoted/suspended. Audit trail: `suspended_reason` + `suspended_at` (set on suspend, cleared on reactivate). Migration: `20260813000000_admin_suspension_enforcement.sql` (idempotent). Full reference: [[docs/AI/ADMIN_SUSPENSION_ARCHITECTURE|Admin Suspension Architecture]].

---

## 🗄️ Data model (auth-relevant)

- `profiles` — `role`, `seller_status` (none/pending/approved/rejected), `suspended` + `suspended_reason`/`suspended_at`, `rejection_reason`, birthday, gender, foot-profile fields (`foot_profile_source`, `foot_size_ph`, `foot_width`, `foot_measurements`), Tier 1 columns (`id_document_url`, `selfie_url`, `cufmai_member_id`, `barangay_proof_url`, `store_name`, `store_description`, `payout_method`, `payout_details`). FK → `auth.users`.
- `seller_business_docs` — one row per profile: `dti_cert_url`, `bir_cor_url`, `permit_url`, `verification_status`, timestamps.
- Storage: `seller-verification-docs` (**private**, policies key off first path segment `{userId}`; reads via `createSignedUrl`).

## 🔐 Security / RLS

- `profiles`: read all, update own; admin update any.
- Suspension migration redefines `is_admin()`/`is_seller_or_admin()` — nearly every elevated policy routes through them, so the ban propagates without per-table edits.
- Guard triggers `prevent_admin_self_lockout` / `protect_last_admin`.

## ⚠️ Gotchas

1. **Legacy users have NULL Tier-1 / foot fields** — never treat missing data as an error state.
2. Duplicate email surfaces inline at Step 1 **and** authoritatively at `auth.signUp` (final submit).
3. `AnimatedSwitcher` + GlobalKeys: each seller step needs its **own** Form key — sharing one crashes with "Duplicate GlobalKey".
4. Customer onboarding is not a hard gate — account creation completes before the foot-profile screen; `pushReplacement` keeps the stack clean.
5. `foot_profile_source` semantics: `ar_scan` > `manual` > `skipped`/NULL (banner shows).
6. Birthday sent as local `YYYY-MM-DD` (`formatBirthdayForDb`) to avoid midnight UTC shifts.
7. Auth policies in `admin-portal/supabase/admin_policies.sql` must stay in sync with the redefined `is_admin()` or they silently downgrade the ban.

## 📚 Deep-dive docs

- [[docs/AI/SIGNUP_ARCHITECTURE|Signup architecture]] — full signup/seller/tiered-verification reference
- [[docs/SIGNUP_ARCHITECTURE|Signup architecture (top-level copy)]]
- [[docs/AI/ADMIN_SUSPENSION_ARCHITECTURE|Admin suspension & enforcement]] — full three-layer reference
- [[docs/AI/PROFILE_ARCHITECTURE|Profile architecture]]
- [[docs/AI/MY_PROFILE_ARCHITECTURE|My Profile architecture]]
- [[docs/PROJECT_HANDOFF|Project Handoff — §Auth & Session decisions]] — force sign-out, 5× retry, biometric clearing

## 🔗 Related

- [[obsidian/MOCs/04 - Admin Portal|🛡️ Admin Portal]] — role & suspension UI
- [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database & Supabase]] — `profiles` RLS, migrations
