# Threat Analysis Review — SoleVision / CUFMAI

**Source document:** `threat-analysis (2).pdf` (authored ~Aug 31 – Sep 1, 2026)
**Review date:** September 3, 2026
**Last updated:** September 3, 2026 (T3 remediation completed + verified live)
**Reviewer:** Codebuff (AI pair-programmer)
**Scope:** Cross-checked every threat row against the actual codebase (Flutter app, React admin portal, Supabase schema/migrations/Edge Functions).

---

## 1. Bottom line

The PDF is a solid, readable STRIDE-style threat model — the right assets were chosen (user accounts, seller verification documents, admin functions, payments, availability) and the risk scoring (Likelihood × Impact, 1–25) is standard and sane.

**The main issue: it is partially out of date the moment it was written.** Several rows recommend controls that this repo already implements — in some cases with code merged *the same week* (Aug 29 – Sep 1). Either the model was written against an earlier snapshot, or the hardening work landed in parallel. If this document is being submitted or graded, it needs a status column, because as written it understates what is already in place.

It also misses the two or three risks that are *actually* highest today (see §4): the manual gateway-free GCash confirmation path, the hardcoded MapTiler API key, and the absence of any rate limiting.

---

## 2. Row-by-row assessment against the codebase

Scoring scale from the PDF: **1–5 Low · 6–12 Medium · 13–19 High · 20–25 Critical**.

### T1 — User account: unauthorized access (Risk 12 · Medium)

**Status: ✅ Largely mitigated — the suggested control already shipped.**

The PDF's own suggested control — *"existing 3–5 failed-login-attempt limit with temporary restriction, monitor repeated failed attempts"* — is implemented:

- `failed_logins` table with lockout tracking: migrations `20260829100000_add_failed_logins_table.sql`, `20260829110000_fix_failed_logins_rls_and_attempt_count.sql`, `20260829120000_fix_failed_logins_rls_for_preauth.sql` (Aug 29).
- Server-side enforcement in `lib/services/auth_service.dart` (`_lockoutMinutes = 30`, locked_until, attempt counter reset on expiry) plus a mirrored local lockout in `lib/providers/auth_provider.dart` (SharedPreferences) so the client stays locked even offline.
- User-facing `LockoutOverlay` widget + lockout **push notification and email** (`send-lockout-email` Edge Function).
- Admin monitoring of repeated attempts already exists: `lib/screens/admin/intruder_suspicious_login_screen.dart` reads real data from `failed_logins`, with "clear all lockouts".

**Remaining gaps (small):**
- No minimum password-strength rule found anywhere in the app or client validation. Supabase's default minimum is only 6 chars unless raised in **Auth → Settings → Security** (server-side — do it there, not just in the app).
- No 2FA / MFA. For a marketplace with seller payout-adjacent data this is the single best next step for this row.

### T2 — Seller verification documents: information disclosure (Risk 15 · High)

**Status: ✅ Largely mitigated — matches the PDF's own control list.**

- Documents live in a **private** bucket `seller-verification-docs` (`lib/services/verification_document_service.dart`: `publicBucket: false`), accessed only via **signed URLs** — never public URLs. This satisfies "secure storage + protect data during transmission."
- Upload validation is defense-in-depth: 10 MB cap, MIME-type checks, and **magic-byte (file signature) verification** reading actual bytes; server-side bucket MIME types back this up.
- Access control is server-side: RLS with the recursion-free `public.is_admin()` helper, and the bucket lockdown landed explicitly in `20260901000000_lock_down_storage_buckets.sql` (Sep 1).

**Remaining gaps (verify + small):**
- Audit the storage RLS policies in that Sep 1 migration and confirm a **non-admin authenticated user cannot list/read** other sellers' documents (test with a throwaway account, not just by reading SQL).
- Confirm signed URLs expire with a short TTL and are generated on demand per admin view (never cached/embedded in pages that could be screenshotted or indexed).
- Admin portal views these via the **anon key + RLS** (`admin-portal/src/lib/supabase.js`), which is correct — no service-role key in the browser. Keep it that way.

### T3 — Seller application records: data tampering (Risk 12 · Medium)

**Status: ✅ Mitigated — remediated September 3, 2026 and verified live.**

Two concrete problems existed (confirmed with real PostgREST probes on Sep 3, 2026):

1. **Post-submission content edits allowed.** With the application stored on `profiles` (`seller_status`: `none`/`pending`/`approved`/`rejected` — there is **no dedicated `seller_applications` table**), the "Users can update their own profile" policy let an applicant PATCH `store_name` and even swap verification-document URLs (`id_document_url`, `selfie_url`, `product_photo_urls`) while `pending` — both returned HTTP 204. (Self-changing `seller_status` itself was already blocked by the Sep 1 `guard_profiles_sensitive_columns` trigger.)
2. **No audit trail.** Approve/reject are raw table UPDATEs from the admin portal; nothing recorded who changed an application's status, when, or from/to what.

**Fixes shipped (all applied to the live DB + verified):**

- `20260903000000_lock_seller_application_after_submit.sql` — extends `guard_profiles_sensitive_columns` so the owner cannot edit application-content columns (store details, verification-doc URLs, `id_type`, `cufmai_member_id`, `rejection_reason`) once `seller_status` is `pending`/`approved`. `rejected` (re-apply) and `none` (draft) stay editable; admins bypass via `is_admin()`. Verified: content PATCH on `pending` → 400 with lock message; on `none` and `rejected` → 204.
- `20260903010000_add_seller_application_audit_log.sql` — `seller_application_audit_log` table (profile_id, actor_id, action, previous_status, new_status, notes, created_at) + an `AFTER UPDATE OF seller_status` trigger as the **only** write path (SECURITY DEFINER). RLS: admin SELECT only; direct INSERT/UPDATE/DELETE revoked from every role incl. service_role. Verified: admin approve/reject via the real portal API path wrote rows with correct actor + timestamps; reviewer notes captured from `profiles.rejection_reason`; direct INSERT blocked (403) for both admin and non-admin.
- `20260903020000_audit_initial_application_submission.sql` — `AFTER INSERT` trigger logging the initial `submitted` event. Needed because this project has **no signup trigger** pre-creating profiles, so first-time submissions take the INSERT branch and the UPDATE trigger never sees them. Verified: fresh submit wrote a `submitted` row with the applicant as actor.

**Fully verified live:** `submitted` (actor = applicant), `approved` (actor = admin), `rejected` (actor = admin, notes captured), direct INSERT 403 for everyone, non-admin SELECT → 0 rows, admin SELECT → all rows. Test data (5 throwaway accounts) created and deleted during verification; audit log cascade-emptied.

**⚠️ Related regression found (out of T3 scope, not fixed):** the Sep 1 status guard blocks the owner's own upsert from `rejected` → `pending`, so the re-apply flow (`completeSellerApplication`) currently fails with `Cannot change your own seller_status.` — confirmed live. Needs a separate fix (allow owner status change `rejected` → `pending` only).

### T4 — Administrator functions: elevation of privilege (Risk 10 · Medium)

**Status: ✅ Strong — this is the best-covered row in the model.**

- Server-side `public.is_admin()` SECURITY DEFINER helper with `REVOKE EXECUTE … FROM PUBLIC` and targeted grants (`supabase/schema.sql`), used in `FOR UPDATE`/`FOR SELECT` RLS policies on `profiles`, `stores`, `orders`, `sales_transactions`, etc. — no client-side trust.
- Admin-only destructive path (`admin_delete_user`) is a guarded SECURITY DEFINER function (`20260817120000_admin_delete_user.sql`).
- Least privilege was tightened again on Sep 1 in `20260901010000_tighten_profiles_rbac.sql`.
- Admin portal uses the anon key + RLS rather than the service-role key — so admins exercise exactly the permissions their account has. **No service-role key in browser code: confirmed.**
- Suspension enforcement migration (`20260813000000_admin_suspension_enforcement.sql`) further hardens admin control over bad actors.

**Remaining gap (minor):** the seller-application audit log (T3) now covers status changes, but there is no **generic admin-audit log** for other privileged actions (user deletion, suspension, product/store moderation). A small `admin_audit_log` writing actor + action + timestamp on sensitive admin operations would close this row completely.

### T5 — Payment: financial fraud / unauthorized payment activity (Risk 15 · High)

**Status: ⚠️ The PDF's premise is stale — but the residual risk is real and is the #1 thing I'd work on.**

The PDF says the payment mechanism *"is not yet finalized"* — **that is no longer true.** As of the Aug 9 migration `20260809000000_revive_paymongo_online_gcash.sql` and the Edge Functions, the app has a production-grade gateway flow:

- PayMongo-hosted **Checkout Sessions** created server-side in Edge Functions with the **secret key never touching the client** (`supabase/functions/_shared/paymongo.ts` — Basic-auth secret header server-side only).
- `gcash-webhook` Edge Function with **mandatory HMAC verification** of the `Paymongo-Signature` header (whsk_…), refusing to write anything on an invalid signature, and auditing/spam-guarding repeated bad signatures.
- Orders start in `awaiting_payment`, transition only after a verified webhook; `payment_verified_at`, fee breakdowns (`paymongo_fee_amount`, `gcash_fee_amount`, `net_amount`), and an admin transactions screen for monitoring. This satisfies nearly the entire control list: trusted gateway ✅, payment data protected ✅, server-side transaction validation ✅, transaction monitoring ✅.

**The real residual risk the PDF doesn't mention:** the app also runs a **gateway-free "direct GCash" flow** (`lib/services/direct_gcash_service.dart`, `gcash_payment_queue_screen.dart`). The customer submits a **reference number + screenshot**, and the *seller manually cross-checks in their own GCash app and confirms*. Fraud concentrates exactly there:

- A customer can submit a made-up or *reused* reference number (same ref, second order).
- A ref number is only bound to an amount by the seller's eyeballing of a screenshot.

**Action (highest priority in this whole review):**
1. Server-side **dedupe on `gcash_reference_number`** — reject a ref already used on a confirmed order (cheap, kills the reuse attack).
2. Where possible, have the queue screen pre-fill/validate the expected amount next to the seller's confirm action.
3. Keep pushing customers to the PayMongo-hosted path (it is the auditable one) and treat the manual flow as fallback-only; add an audit trail of seller confirm/reject decisions.

### T6 — System availability: denial of service (Risk 12 · Medium)

**Status: 🟡 Genuinely open — no code-level rate limiting.**

- Login brute force is handled (T1), and the webhook has spam protection on rejected signatures — but there is **no rate limiting** on Edge Functions, the search/geocoding surface, or other anonymous endpoints.
- Supabase platform limits provide a backstop, but nothing application-level monitors "unusual request patterns" or throttles specific endpoints.

**Action:** add per-IP/per-user throttling on the public-function surface, watch Supabase logs for anomalies, and keep recovery procedures (restore drills) documented. See also the concrete exposure in §3, which is the DoS risk most likely to actually bite today.

---

## 3. Real gaps the PDF does not cover at all

These are things I found in the code that a refresh of the model should include:

1. **🔴 Hardcoded third-party API key (client-side secret).** The MapTiler geocoding/tiles key is compiled into the app in `lib/constants/app_constants.dart:27` (`AppConstants.maptilerKey`) and sent as a query param from `add_edit_address_screen.dart`. Anyone who unpacks the APK extracts it and can burn geocoding/tile quota or use it from their own app. Fix: proxy through an Edge Function (or restrict the key by domain/HTTP referrer in MapTiler) and remove the constant from the client. This is both a "secret hygiene" and a DoS/quota-abuse issue.
2. **Manual GCash flow fraud surface** (see T5) — the model's payment row should be rewritten around this, not "not yet finalized."
3. **Deep-link / app-link spoofing.** The app handles `solvision://checkout/gcash/*` deep links and cold-start redirects (`main.dart`). Worth a row: can a crafted link push a user into a payment or phishing-looking screen?
4. **Push-notification channel abuse** — device-token tampering / notification spoofing is used as a vector (lockout notifications already flow through it); worth a row now that it carries security messaging.
5. **No generic admin audit log** — the seller-application audit log (T3, shipped Sep 3) covers status changes only; other privileged admin actions (user deletion, suspensions, moderation) are still unlogged.
6. **Dependency/CVE hygiene** — not mentioned in the model; worth a low-severity row (Flutter packages, `supabase-js`, Deno edge runtime deps).

---

## 4. What I'd do next (in priority order)

| # | Action | Risk addressed | Effort |
|---|--------|----------------|--------|
| 1 | Harden the manual GCash path: server-side ref-number dedupe, amount binding, confirm/reject audit trail | T5 (15) | Small–Medium |
| 2 | Enable real password policy + MFA at Supabase Auth level (server-side), enforce min 8 chars in app validators | T1 (12) | Small |
| 3 | Move the MapTiler key server-side / restrict by referrer; remove from `app_constants.dart` | T6 + new gap | Small |
| 4 | Verify storage RLS + signed-URL TTLs for `seller-verification-docs` with a real non-admin test | T2 (15) | Small |
| 5 | Add a **generic** `admin_audit_log` for privileged admin actions beyond seller applications (user deletion, suspensions, moderation) | T4 (10) | Medium |
| 6 | Rate limiting + monitoring on public Edge Functions | T6 (12) | Medium |
| 7 | **Refresh the PDF/threat matrix**: add a status column per control, re-score (several Mediums likely drop to Low now), and add the §3 rows so the document reflects the current build | — | Small |

---

## 5. What the model gets right

- Correct asset inventory for a marketplace app — most student threat models miss document-handling or seller-application integrity entirely.
- Honest scoring: Highs on documents and payments, not padded to Critical.
- The suggested controls are the *right* controls (RBAC, signed storage, webhook/transaction validation, rate limiting) — the project has simply already executed a large share of them.

**Overall verdict:** good threat model, written ~a week behind the code. Treat §2 statuses as the correction layer, and let §4's list be the working backlog.
