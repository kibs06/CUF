# GO-LIVE PRELAUNCH CHECKLIST (before real users)

**Date:** September 3, 2026 (updated Sep 5, 2026 — T5 manual-GCash closure added to pending applies + done list)
**Status:** Open — items below must be resolved before the app takes real customers.
**Context:** Compiled from the T6 hardening, gcash-webhook secret outage, and reconciliation session. The live PayMongo account ("Carcar United Footwear") exists with `sk_live_`/`pk_live_` keys, but the app has only ever processed TEST-mode payments.

---

## 🔴 Critical — resolve before real money flows

1. **PayMongo LIVE wiring — verify + test end-to-end**
   - The LIVE webhook was created **Sep 3** at URL `https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/gcash-webhook`. Confirm it exists on the LIVE environment and is subscribed to **`checkout_session.payment.paid`** (and ideally `payment.paid` + `payment.failed` as defensive events).
   - Confirm the project secret **`PAYMONGO_SECRET_KEY` is the LIVE key (`sk_live_…`)** and `PAYMONGO_LIVEMODE=true`. ⚠️ The only recorded payment intent (`pi_BA8zVibfwg16E4qhkfG1bnEi`, Aug 19) was created with a **TEST** key (`livemode: false`) — if the secret is still test, live checkouts will create test sessions or fail.
   - Do a **real end-to-end live test** before launch: place a small real GCash order → pay → confirm `gcash-webhook` returns 200 and the order finalizes (`status: pending`, `payment_status: paid`, `payment_verified_at` set, seller notified). PayMongo's dashboard "Send test webhook" only exercises delivery, not a real payment.
   - `PAYMONGO_WEBHOOK_SECRET` is now a project-wide secret (verified: bad signature → 401). Keep it project-wide, not function-scoped.

2. **MapTiler tiles are broken through the proxy**
   - Geocoding works via `geocode-proxy`, but **raster tiles return 403** from Supabase's servers with the current key (MapTiler error tile). Real users' map pickers will show error tiles.
   - Fix: generate a **server key** in the MapTiler dashboard (no referrer/IP restrictions, tiles + geocoding enabled) and update `MAPTILER_API_KEY`. Also **rotate/delete the old key** — it shipped inside app builds and git history.

3. **Public Edge Functions have NO authorization** (anonymous callers can forge requests)
   - `send-notification-push`, `send-message-push`, `create-gcash-payment`, `send-approval-email`, `send-lockout-email` are deployed `verify_jwt = false` and trust caller-supplied bodies (recipient IDs, user IDs, order IDs). Once real users exist, strangers could: push fake notifications to any user, spoof seller/customer messages, trigger approval/lockout emails, or create PayMongo charge attempts against arbitrary order IDs.
   - Fix (separate task): enable JWT verification and/or validate the caller's identity server-side. Rate limiting (shipped) only caps volume — it does not authenticate.

## 🟡 Should fix before launch

4. **Rate-limit + T5 migrations not confirmed applied.** `20260903030000_add_rate_limiting.sql` must be run (SQL Editor) + recorded in the migration ledger, or all the new rate limiters **fail open** (functions work, but there is no protection). **Also apply `20260905000000_fix_t5_manual_gcash_dedupe_audit.sql`** — until it runs, the manual-GCash reference dedupe and seller decision audit trail do not exist server-side (code shipped Sep 5, commit `6dee84b`). Also confirm the T3 ledger inserts (20260903000000–20260903020000) were recorded.
5. **Seller re-apply regression (T3):** the Sep 1 status guard blocks a rejected seller's re-submission (`rejected → pending` raises `Cannot change your own seller_status.`). Real rejected applicants cannot re-apply until fixed.
6. **Stale `awaiting_payment` orders are never expired.** The test order from Aug 19 sat in `awaiting_payment` for 2 weeks (no expiry sweep ran for PayMongo checkout sessions). Ensure the expiry/cancel cron is applied before launch so abandoned checkouts auto-cancel and stock is never held.
7. **Admin account hygiene:** the admin login (keithabalo03@gmail.com) was shared in plaintext during this session — change the password before launch.

## ✅ Already done (verified this session)

- `gcash-webhook` secret restored as project-wide; function healthy (bad signature → 401).
- LIVE webhook endpoint created (verify events/env per item 1).
- Reconciliation closed: 51 orders, exactly 1 was in `awaiting_payment` — a TEST-mode payment (₱410.25, Aug 19) confirmed paid on PayMongo, **cancelled with a full audit note** (`53194fe1-5633-4066-bda5-c13d6ce8fe1f`). No other orders touched.
- T6 code shipped: `geocode-proxy` (MapTiler proxy + per-IP rate limiting), shared `_shared/rate_limit.ts`, rate limiting wired into 9 public functions, MapTiler key removed from the Flutter client (`app_constants.dart`), both map screens call the proxy. Rate-limit counters need migration item 4 to be active.
- **T5 manual-GCash fraud surface closed in code (Sep 5, commit `6dee84b`):** reference-number dedupe on paid orders (23505 → clear seller error), admin-only `gcash_payment_decision_audit` trail written by POS confirm trigger + confirm/reject RPCs, expected-amount banner above the seller's Confirm/Reject buttons, and `create_gcash_checkout` EXECUTE revoked (no new manual orders from anywhere; legacy Aug 8–9 orders can still resolve). Activation requires migration item 4; pgTAP suite `supabase/tests/t5_manual_gcash_dedupe_audit.test.sql` runs in CI.
- `supabase/config.toml` now documents `verify_jwt = false` for every deployed-public function (prevents accidental JWT flips on redeploy).
