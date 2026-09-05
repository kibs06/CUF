# SoleVision Threat Review — Executive Summary

**What this is:** A short, plain-language version of the security review, written so a client, stakeholder, engineer, or AI agent can understand the state of security in under 5 minutes.

**What was reviewed:** The threat model in `threat-analysis (2).pdf` (authored Aug 31 – Sep 1, 2026) cross-checked against the actual app code (Flutter app, React admin portal, Supabase backend).

**Review date:** Sep 3, 2026
**Snapshot:** 4 of 6 threat areas largely protected ✅ · 2 areas still have open items before launch ⚠️ · no critical open vulnerability in the gateway payment path.

> **Full technical detail lives in [THREAT_ANALYSIS_REVIEW.md](./THREAT_ANALYSIS_REVIEW.md).** Each section below links to it. Start here; go there when you need file names, migrations, and verification evidence.

---

## 1. Bottom line — 30-second read

- The threat model is **solid and honestly scored**, but it describes the app roughly **a week behind the code** — several controls it *recommends* were **already built and verified** when it was written.
- **Best-protected areas:** seller verification documents, seller applications, and admin functions — all enforced server-side, not in the app.
- **Must-fix before real customers:** the manual "direct GCash" payment path (fake reference numbers are possible), switching payments from **test keys to live keys**, and applying a few shipped fixes to the **live server** (rate limits, map key).
- **Good news:** the Sep 3 webhook incident is resolved — forged payment notifications are now rejected, and all orders were reconciled with zero collateral.

**Risk scale used by the model** (1–25): 1–5 Low · 6–12 Medium · 13–19 High · 20–25 Critical.

---

## 2. Scorecard at a glance

| # | Threat (plain English) | Risk | Status | One-line verdict |
|---|------------------------|------|--------|------------------|
| T1 | Someone else signs in to a user's account | Medium (12) | ✅ Mostly protected | Lockouts + alerts exist; no strong-password rule or 2FA yet |
| T2 | Seller ID documents are seen by the wrong people | High (15) | ✅ Mostly protected | Private storage + expiring one-time links; final verify step pending |
| T3 | Seller applications are edited or faked after submission | Medium (12) | ✅ Fixed & tested live | Applications lock after submit; every approve/reject is logged |
| T4 | Admin tools are abused to gain extra power | Medium (10) | ✅ Well protected | Server-side admin checks; no master key in the browser |
| T5 | Payment fraud / fake payments | High (15) | ⚠️ Partly — top priority | Gateway path is solid; manual GCash path + live keys remain |
| T6 | App overloaded or taken down (abuse) | Medium (12) | ⚠️ Code shipped | Rate limits + secret key moved server-side; live apply + map key remain |

---

## 3. Threat-by-threat detail

### T1 — Account break-ins (Risk 12 · Medium)
**Status: ✅ Mostly protected.**

- **In place:** Wrong-password **lockouts** (30 min) enforced on both server and app; account owner gets a **notification + email** when locked; admins have a "suspicious logins" screen with a clear-all-lockouts action.
- **Still open:** No minimum **password-strength rule**, and no **two-factor authentication (2FA)** — the single best next step for this area.
- **Tech note:** `failed_logins` table + `auth_service.dart`; `LockoutOverlay` + `send-lockout-email`; `intruder_suspicious_login_screen.dart`. Detail → [full review §T1](./THREAT_ANALYSIS_REVIEW.md).

### T2 — Seller ID documents leaked (Risk 15 · High)
**Status: ✅ Mostly protected — verify step remains.**

- **In place:** Documents sit in a **private** storage bucket opened only through **short-lived, one-time links** (never public URLs); uploads are validated by type *and* actual file content; only admins can reach them (server-side rules).
- **Still open:** Confirm with a real **non-admin test account** that sellers can't view each other's documents, and that links expire quickly and are generated on demand.
- **Tech note:** `seller-verification-docs` bucket (`publicBucket: false`), signed URLs, RLS `is_admin()`; migration `20260901000000_lock_down_storage_buckets.sql`. Detail → [full review §T2](./THREAT_ANALYSIS_REVIEW.md).

### T3 — Seller applications edited/faked after submission (Risk 12 · Medium)
**Status: ✅ Fixed Sep 3 and verified on the live app.**

- **In place:** Once submitted, a seller **cannot edit** store details or swap verification-document links (they could before the fix — both were confirmed live); every approval/rejection is now **logged with who, when, from/to what status, and notes**; even the admin tool can't write log rows directly.
- **Still open:** The fix blocks a rejected seller's **re-apply** flow (`rejected → pending`) — tracked as backlog item #6 below.
- **Tech note:** Migrations `20260903000000`–`20260903020000` + `seller_application_audit_log` trigger; verified live with PostgREST probes + 5 throwaway accounts (deleted after). Detail → [full review §T3](./THREAT_ANALYSIS_REVIEW.md).

### T4 — Admin function abuse (Risk 10 · Medium)
**Status: ✅ Well protected — best-covered area in the model.**

- **In place:** Admin rights are enforced **server-side** (database-level checks, not app trust); the admin portal uses restricted keys + per-account rules — **no master database key in the browser**; destructive actions are guarded; bad-actor suspension is enforced.
- **Still open:** No **general admin audit log** yet — deletions, suspensions, and moderation actions aren't recorded (application status changes now are, via T3).
- **Tech note:** `public.is_admin()` SECURITY DEFINER; `20260817120000_admin_delete_user.sql`; `20260813000000_admin_suspension_enforcement.sql`. Detail → [full review §T4](./THREAT_ANALYSIS_REVIEW.md).

### T5 — Payment fraud (Risk 15 · High — **top priority**)
**Status: ⚠️ Gateway payments hardened Sep 3; the manual GCash path is the biggest remaining fraud surface.**

- **In place:** Real **PayMongo checkout** flow — payments are created server-side (secret key never in the app) and an order only becomes "paid" after a **verified webhook** with a checked signature (forged calls → rejected). After the Sep 3 webhook incident: the **live webhook is now registered**, the secret is stored project-wide so redeploys can't drop it, the function is rate-limited, and all **51 orders were reconciled** (the single stuck one was a developer *test* payment and was cancelled with a full audit note — nothing else touched).
- **Still open (before real money):**
  1. The **manual "direct GCash" path** — customer types a reference number + screenshot, seller confirms by eye. Fake or **reused reference numbers** are possible → add server-side dedupe + expected-amount check + a log of confirm/reject decisions.
  2. The app still runs on **PayMongo test keys** — switch to live keys, redeploy, and run one real end-to-end payment before launch.
- **Tech note:** `gcash-webhook` HMAC + 600/min rate limit; `_shared/paymongo.ts`; `direct_gcash_service.dart`; launch steps in [GO_LIVE_PRELAUNCH_CHECKLIST.md](./GO_LIVE_PRELAUNCH_CHECKLIST.md). Detail → [full review §T5](./THREAT_ANALYSIS_REVIEW.md).

### T6 — App overloaded / taken down (Risk 12 · Medium)
**Status: ⚠️ Code shipped Sep 3 (CI green); two live-side items remain.**

- **In place:** The **map API key was removed from the app** (anyone unpacking the app could have stolen it) and moved into a server-side proxy; **rate limits** now protect the public functions (per IP, tuned per function, safe even under bursts, and they "fail open" so a hiccup never breaks the app).
- **Still open:** Apply the rate-limit counters **to the live database** (until then limits log but don't block); provision a **server map key** so maps actually load (tiles currently error); **rotate the old key** still visible in git history.
- **Tech note:** `geocode-proxy` Edge Function; `20260903030000_add_rate_limiting.sql`; `_shared/rate_limit.ts` wired into 10 handlers. Detail → [full review §T6](./THREAT_ANALYSIS_REVIEW.md).

---

## 4. Risks the model missed (found during review)

| # | Risk | Status |
|---|------|--------|
| 1 | 🔴 Map API key hardcoded inside the app | ✅ **Fixed Sep 3** — moved server-side; rotate old key still pending |
| 2 | Manual GCash path: fake/reused reference numbers | ❌ **Open — top priority** (see T5) |
| 3 | Deep-link spoofing (`solvision://checkout/…` — could a crafted link push a user into a fake payment screen?) | ❌ Unassessed |
| 4 | Push-notification/email functions callable by strangers with forged content | ⚠️ Rate-limited only — still need authentication (backlog #2) |
| 5 | No general admin audit log (deletions, suspensions, moderation) | ❌ Open (backlog #8) |
| 6 | Dependency / security-update hygiene | ❌ Open, low severity |
| 7 | Abandoned checkouts never expire — orders stuck in "awaiting payment" forever | ❌ Open (backlog #7) |

---

## 5. Action plan — what to do next (priority order)

| # | Action (plain English) | Protects against | Effort | Status |
|---|------------------------|------------------|--------|--------|
| 1 | Turn on the shipped rate limits on the live server | Overload / abuse (T6) | Small | ❌ Pending apply |
| 2 | Require real login before the notification/email/payment functions can be called | Forged messages & payment attempts | Small–Medium | ❌ Open |
| 3 | Set up a proper server map key + rotate the old leaked one | Map quota theft, broken maps (T6) | Small | ❌ Open |
| 4 | Switch payments to **live** keys + test one real payment end-to-end | Real-money readiness (T5) | Small | ❌ Pre-launch |
| 5 | Dedupe/validate reference numbers on the manual GCash path + log seller confirm/reject | Fake/reused payments (T5) | Small–Medium | ❌ Open |
| 6 | Fix rejected sellers being unable to re-apply | Seller onboarding (T3) | Small | ❌ Open |
| 7 | Auto-cancel abandoned checkouts after a timeout | Stuck orders, held stock (T5) | Small | ❌ Open |
| 8 | Add a general admin audit log for privileged actions | Admin accountability (T4) | Medium | ❌ Open |
| 9 | Add a strong-password rule + two-factor authentication | Account break-ins (T1) | Small | ❌ Open |
| 10 | Verify document privacy with a real non-admin test | Document leaks (T2) | Small | ❌ Open |
| 11 | Refresh the PDF/threat matrix to match the current build | Doc accuracy | Small | ❌ Open |

> ✅ **Completed Sep 3** (removed from the backlog): T3 application lock + audit log, T6 rate limiting + server-side map key, webhook secret restored + live webhook registered, order reconciliation. See §6.

---

## 6. Already done (Sep 3, 2026 — verified)

- **Seller applications hardened + tested live** (T3): content locks after submit; full audit log for approvals/rejections.
- **Abuse protection shipped** (T6): rate limiting across 10 functions + map key moved out of the app (CI green, 527 tests passing).
- **Payment webhook incident closed** (T5): live webhook registered, secret stored project-wide, forged signatures rejected (verified), 51 orders reconciled with zero collateral.
- **CI cleanup**: dead code removed so automated checks are clean again.

---

## 7. What the model got right

- **Right assets picked** — most student threat models skip document handling and application integrity entirely.
- **Honest scoring** — Highs on documents and payments, not padded up to Critical.
- **Right suggested controls** (access rules, private storage, payment verification, rate limits) — the project had simply already executed a large share of them.

**Overall verdict:** a good threat model written about a week behind the code. Treat the statuses above as the correction layer and §5 as the working backlog.

---

## 8. Jargon decoder (non-technical readers)

| Term | Meaning |
|------|---------|
| **Rate limit** | Stops one person/script from hammering a function thousands of times |
| **Webhook + signature** | PayMongo's server calls ours to say "this payment succeeded"; we check its digital signature so fakes are rejected |
| **Signed URL / one-time link** | A private link to a document that expires quickly and can't be shared around |
| **RLS / admin checks** | Rules in the database that decide who may read/write what — enforced even if the app were bypassed |
| **Live vs test keys** | Test keys process fake money; live keys process real money |

---

## 9. Which document to read when

| Your need | Read |
|-----------|------|
| 5-minute overview for a client or stakeholder | **This file** |
| File names, migrations, and verification evidence | [THREAT_ANALYSIS_REVIEW.md](./THREAT_ANALYSIS_REVIEW.md) |
| Everything blocking launch, step by step | [GO_LIVE_PRELAUNCH_CHECKLIST.md](./GO_LIVE_PRELAUNCH_CHECKLIST.md) |

---

*Compiled by Codebuff (AI pair-programmer) — Sep 3, 2026. Companion to the full review; keep this short and let the deep dive carry the detail.*
