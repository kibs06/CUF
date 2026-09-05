# Threat Analysis Review — SoleVision / CUFMAI

> **Short version:** For a client-friendly, ~5-minute read, see [THREAT_ANALYSIS_SUMMARY.md](./THREAT_ANALYSIS_SUMMARY.md). This file is the deep dive (code paths, migrations, verification evidence).

**Source document:** `threat-analysis (2).pdf` (authored ~Aug 31 – Sep 1, 2026)
**Review date:** September 3, 2026
**Last updated:** September 3, 2026 (T3 ✅ verified live · T6 ✅ shipped · webhook incident reconciled — see §6 change log)
**Reviewer:** Codebuff (AI pair-programmer)
**Scope:** Cross-checked every threat row against the actual codebase (Flutter app, React admin portal, Supabase schema/migrations/Edge Functions).

---

## 1. Bottom line

The PDF is a solid, readable STRIDE-style threat model — the right assets were chosen (user accounts, seller verification documents, admin functions, payments, availability) and the risk scoring (Likelihood × Impact, 1–25) is standard and sane.

**The main issue: it is partially out of date the moment it was written.** Several rows recommend controls that this repo already implements — in some cases with code merged *the same week* (Aug 29 – Sep 1). Either the model was written against an earlier snapshot, or the hardening work landed in parallel. If this document is being submitted or graded, it needs a status column, because as written it understates what is already in place.

It also missed the risks that are *actually* highest today: the manual gateway-free GCash confirmation path and the anonymous push/email functions callable with forged bodies. Two of its blind spots — the hardcoded MapTiler key and the absence of any rate limiting — were remediated on Sep 3 (see T6); the rest remain in §4.

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

**Status: ⚠️→✅ The PDF's premise is stale — and since Sep 3 the gateway flow is materially hardened (webhook incident resolved + reconciled, below). The manual gateway-free GCash path remains the top residual fraud surface.**

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

**Operational hardening — Sep 3, 2026 (PayMongo webhook incident + reconciliation):**

- **What actually happened.** `PAYMONGO_WEBHOOK_SECRET` had been function-scoped and was lost during a redeploy, and — the bigger finding — **no webhook was ever registered in PayMongo LIVE** (dashboard showed "No Webhooks yet"). No LIVE delivery was lost; the real gap was that nothing existed to deliver to — which is why the only recorded payment (Aug 19, TEST) was never webhook-confirmed and sat in `awaiting_payment` for two weeks.
- **Fix (verified).** LIVE webhook registered at `…/functions/v1/gcash-webhook`, subscribed to `checkout_session.payment.paid` + `payment.paid` + `payment.failed`; the secret was restored **project-wide** (so a redeploy can't drop it again) and `gcash-webhook` redeployed. Verified live: bogus signature → **401** `invalid signature` (never 500). The webhook additionally gained a per-IP rate limit (600/min) on top of its mandatory HMAC + idempotency + amount-integrity processing.
- **Reconciliation (closed, zero collateral).** All 51 orders reviewed; exactly 1 was in `awaiting_payment` — order `53194fe1…` (₱410.25, Aug 19). The PayMongo API confirmed it was **paid in TEST mode** (`livemode: false`, payment `pay_MbYuBj2NEfw7RM6qhB6eerbE` — a developer test checkout, no real money). It was cancelled **with a full audit note** rather than fulfilled, so no phantom sale or stock movement entered the seller pipeline. No other row was modified.

**Residual T5 state (pre-launch):** `PAYMONGO_SECRET_KEY` is still the **test** key (digest-verified) with `PAYMONGO_LIVEMODE` unset, while the registered webhook is in **LIVE** — so sandbox checkouts won't be webhook-confirmed (they'd fall back to the client-side poll, the exact gap that slipped the Aug 19 order). Before real users: set the `sk_live_…` key + `PAYMONGO_LIVEMODE=true`, redeploy the payment functions, and run one real end-to-end payment; while sandbox-testing, register the same endpoint under TEST too. Full account: `docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md`.

### T6 — System availability: denial of service (Risk 12 · Medium)

**Status: ✅ Mitigated — shipped Sep 3, 2026 (commit `eeba2b6`, CI green). Two live-side follow-ups pending: apply the counter migration to the DB, and swap in a MapTiler key that serves raster tiles.**

Implemented in two parts (root cause first):

**1. Hardcoded MapTiler key removed from the client (root cause).** The key that shipped in `AppConstants.maptilerKey` was deleted from the app. A new `geocode-proxy` Edge Function (`supabase/functions/geocode-proxy/index.ts`) now holds `MAPTILER_API_KEY` as a server-side secret and forwards geocoding + raster tiles; both map screens (`add_edit_address_screen.dart`, `store_location_picker_screen.dart`) call the proxy. The proxy returns only the fields the app consumes, scopes results to the PH bounding box, and rate-limits per IP — search 30/min, tiles 600/min (map panning fires ~8–24 concurrent fetches and stays under it; scripted whole-city scraping does not).

**2. Application-level rate limiting on the public-function surface.** Fixed-window, per-IP counters persisted in Postgres — `function_rate_limits` table + service-role-only `rate_limit_increment` RPC (migration `20260903030000_add_rate_limiting.sql`) and a shared helper (`supabase/functions/_shared/rate_limit.ts`). Wired into **10 function handlers** with per-route limits: `gcash-webhook` 600/min, `product-preview` 120, `validate-upload` 60, `send-notification-push`/`send-message-push` 600, `send-approval-email` 60, `send-lockout-email` 30, `apply-store-schedules` 30, `create-gcash-payment` 30, plus both `geocode-proxy` routes. Counters use atomic upserts (no lost increments under bursts) with opportunistic expiry-row cleanup; the helper **fails open** if the counter store is unreachable, so a misconfiguration never breaks the feature it protects.

**Residual — why this row isn't fully closed yet:**
- The counter migration is **not yet applied to the live DB** (checklist item 4 in `GO_LIVE_PRELAUNCH_CHECKLIST.md`) — until it is, the limiters log-and-allow in production.
- Rate limiting caps *volume*; it does not *authenticate*. `send-notification-push`, `send-message-push`, `send-approval-email`, `send-lockout-email`, and `create-gcash-payment` are still callable by anonymous callers with forged bodies (§4 #2).
- MapTiler **raster tiles still return 403** through the proxy (geocoding works) — the current key isn't permitted for server-side tile fetches; needs a server key. The old client key also remains in git history → rotate it.
- The three JWT-guarded payment functions (`create-gcash-payment-intent`, `get-payment-status`, `request-account-deletion`) sit behind user auth but don't carry the IP limiter — acceptable now; per-user limits are a later nicety.

---

## 3. Real gaps the PDF does not cover at all

These are things I found in the code that a refresh of the model should include:

1. **🔴 Hardcoded third-party API key (client-side secret) — ✅ remediated Sep 3, 2026.** The MapTiler key was compiled into the app (`AppConstants.maptilerKey`, used by `add_edit_address_screen.dart`); anyone unpacking the APK could extract it and burn geocoding/tile quota. Fixed by moving the key server-side into the `geocode-proxy` Edge Function and deleting it from the client (details in T6). **Residual:** the old key is still in git history (committed Jul 2026) → rotate/delete it in MapTiler; and raster tiles currently 403 through the proxy until a proper server key is set.
2. **Manual GCash flow fraud surface** (see T5) — the model's payment row should be rewritten around this, not "not yet finalized."
3. **Deep-link / app-link spoofing.** The app handles `solvision://checkout/gcash/*` deep links and cold-start redirects (`main.dart`). Worth a row: can a crafted link push a user into a payment or phishing-looking screen?
4. **Push-notification channel abuse** — device-token tampering / notification spoofing is used as a vector (lockout notifications already flow through it); worth a row now that it carries security messaging. Rate limiting (shipped Sep 3) caps volume, but the push/email functions remain anonymous with forged bodies — see §4 #2.
5. **No generic admin audit log** — the seller-application audit log (T3, shipped Sep 3) covers status changes only; other privileged admin actions (user deletion, suspensions, moderation) are still unlogged.
6. **Dependency/CVE hygiene** — not mentioned in the model; worth a low-severity row (Flutter packages, `supabase-js`, Deno edge runtime deps).
7. **Abandoned PayMongo checkouts never expire.** Found during the Sep 3 reconciliation: a checkout a customer abandons stays in `awaiting_payment` indefinitely — the Aug 19 test order sat for two weeks. Worth a row: an expiry sweep/cron for PayMongo checkout sessions (mirroring the existing GCash one) before real users.

---

## 4. What I'd do next (in priority order)

| # | Action | Risk addressed | Status / effort |
|---|--------|----------------|-----------------|
| 1 | Apply migration `20260903030000` to the live DB + record in `MIGRATIONS_LIVE_STATUS.md` — until then every rate limiter fails open | T6 (12) | **Pending live apply** · Small |
| 2 | Authenticate the anonymous Edge Functions (`send-message-push`, `send-notification-push`, `create-gcash-payment`, `send-approval-email`, `send-lockout-email`) — enable JWT or add server-side identity checks | New gap (forged bodies) | Small–Medium |
| 3 | MapTiler: provision a server key that serves raster tiles (fix the current 403) and rotate the old key still in git history / old builds | T6 + new gap | Small |
| 4 | Flip payments to LIVE before real users (`PAYMONGO_SECRET_KEY=sk_live_…`, `PAYMONGO_LIVEMODE=true`, redeploy payment functions) + one real end-to-end payment; register the TEST webhook for sandbox testing | T5 (15) | Small · pre-launch |
| 5 | Harden the manual GCash path: server-side ref-number dedupe, amount binding, confirm/reject audit trail | T5 (15) | Small–Medium |
| 6 | Fix the seller re-apply regression (`rejected → pending`) found during T3 verification | T3 (12) | Small |
| 7 | Add an expiry sweep for stale PayMongo `awaiting_payment` orders | T5 + §3 #7 | Small |
| 8 | Add a **generic** `admin_audit_log` for privileged admin actions (user deletion, suspensions, moderation) | T4 (10) | Medium |
| 9 | Enable real password policy + MFA at Supabase Auth level (server-side) | T1 (12) | Small |
| 10 | Verify storage RLS + signed-URL TTLs for `seller-verification-docs` with a real non-admin test | T2 (15) | Small |
| 11 | **Refresh the PDF/threat matrix**: add a status column per control, re-score (several Mediums likely drop to Low now), and add the §3 rows so the document reflects the current build | — | Small |

> ✅ **Done on Sep 3** (removed from the backlog): T3 remediation (application lock + audit log — applied live + verified), rate limiting on public Edge Functions + MapTiler key moved server-side (T6 — committed, CI green, live-DB apply still pending per #1), webhook secret restored + LIVE webhook registered, order reconciliation. See §6.

---

## 5. What the model gets right

- Correct asset inventory for a marketplace app — most student threat models miss document-handling or seller-application integrity entirely.
- Honest scoring: Highs on documents and payments, not padded to Critical.
- The suggested controls are the *right* controls (RBAC, signed storage, webhook/transaction validation, rate limiting) — the project has simply already executed a large share of them.

**Overall verdict:** good threat model, written ~a week behind the code. Treat §2 statuses as the correction layer, and let §4's list be the working backlog.

---

## 6. Change log

| Date | Change |
|---|---|
| Sep 3, 2026 | **T3 remediated + verified live** — application-content lock + `seller_application_audit_log` (migrations `20260903000000`–`20260903020000`, applied via SQL Editor + PostgREST-probed). |
| Sep 3, 2026 | **T6 remediated** — `20260903030000_add_rate_limiting.sql`, `geocode-proxy`, `_shared/rate_limit.ts` wired into 10 handlers; MapTiler key removed from the client. Committed `eeba2b6`; CI green (flutter analyze + 527 tests; 80-migration apply + RLS canary). Live-DB counter apply still pending (§4 #1). |
| Sep 3, 2026 | **PayMongo webhook incident resolved + reconciled.** LIVE webhook registered; `PAYMONGO_WEBHOOK_SECRET` restored project-wide (verified: bad signature → 401); 51 orders reviewed, the 1 test-paid order cancelled with a full audit note, nothing else touched. Full account: `docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md`. |
| Sep 3, 2026 | **CI debt cleared** (`a793505`) — removed ~200 lines of dead, never-wired confirmation-token scaffold in `auth_service.dart` so `flutter analyze` is clean; no behavioral change. |
