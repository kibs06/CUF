# Online GCash — Test Plan (attempt #4)

> Companion to `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` §9. Everything here runs
> against PayMongo **test/sandbox** keys first. Live keys are the final step only.
>
> Status: server-side pieces built; not yet sandbox-tested (needs sandbox env vars).

---

## 0. Pre-requisites (sandbox)

```bash
supabase secrets set PAYMONGO_SECRET_KEY=sk_test_... \
  PAYMONGO_WEBHOOK_SECRET=whsk_... \
  PUBLIC_RETURN_URL=solvision://checkout/gcash \
  GCASH_PAYMENT_EXPIRY_MINUTES=30

supabase db push                                  # applies 20260808120000_add_online_gcash_payments.sql
supabase functions deploy create-gcash-payment-intent
supabase functions deploy get-payment-status
supabase functions deploy gcash-webhook --no-verify-jwt
```

Register the webhook URL in the PayMongo dashboard with events `payment.paid`,
`payment.failed`; copy the `whsk_…` secret into `PAYMONGO_WEBHOOK_SECRET`.

> ⚠️ **Verify in sandbox before trusting the code:** the exact placement of the
> `return_url` parameter on PayMongo's gcash attach call, and the location of the
> checkout URL (`next_action.redirect.url`). The code reads them defensively; confirm
> against a real sandbox response and adjust if PayMongo's API differs.

---

## 1. Isolated Edge Function tests (curl, before any app wiring)

### 1.1 create-gcash-payment-intent

| # | Case | Expect |
|---|---|---|
| 1.1a | No `Authorization` header | `401` |
| 1.1b | Invalid JWT | `401` |
| 1.1c | Missing/invalid `idempotency_key` | `400` |
| 1.1d | Empty `items` | `400` |
| 1.1e | `product_id` that doesn't exist | `409`, no order created |
| 1.1f | Size with no stock | `409`, no order created |
| 1.1g | Happy path | `200` with `order_id`, `checkout_url`, `client_key`, `expires_at`; order row `status='awaiting_payment'`, `payment_status='pending'`; **no `order_items` rows**; `payment_intents` row `status='pending'` |
| 1.1h | Amount check | order `total_amount` = Σ current product prices + ₱100, **not** the client-sent total (send a bogus total and confirm it's ignored) |
| 1.1i | Double-call same idempotency key | second call returns the same `order_id`/intent (`already_exists: true`) — no second order/intent |
| 1.1j | Second checkout while a pending intent exists (different key) | returns the existing pending intent — no duplicate charge (also enforced at DB level by `uq_payment_intents_one_pending_per_customer`) |
| 1.1j' | Active pending intent exists but for a **different cart** (items_fingerprint mismatch) | `409` with a clear message — the customer is never pushed into paying for the wrong items |
| 1.1l | `PAYMONGO_LIVEMODE=true` set | `payment_intents.livemode` recorded as `true` (audit correctness on live rollout) |
| 1.1k' | **Concurrent race** — fire two requests simultaneously with different idempotency keys | exactly one intent survives; the loser's `payment_intents` insert hits the partial unique index → its duplicate order is cancelled, and it resumes the winner's intent (`already_exists: true`) — no double charge |
| 1.1k | PayMongo down / bad secret | `502`; order closed as `cancelled`/`failed` with reason "Payment gateway error" |

### 1.2 gcash-webhook (security first)

| # | Case | Expect |
|---|---|---|
| 1.2a | No `Paymongo-Signature` header | `401` |
| 1.2b | Forged signature (wrong HMAC) | `401`; logged as `rejected_signature` |
| 1.2c | Valid HMAC but stale timestamp (>10 min) | `401` (replay guard) |
| 1.2d | Tampered body with signature from an older valid body | `401` (signature covers exact bytes) |
| 1.2e | Valid signature, unknown event type | `200`, logged `ignored_unknown` |
| 1.2f | **Duplicate delivery** of the same event id | first → processed; second → `200` no-op (`skipped_duplicate`), no double stock decrement, no duplicate notifications |
| 1.2f' | Retry of an event whose previous attempt crashed mid-materialization (event row `status='failed'`) | re-claimed and reprocessed; materialization is **diff-based** — only snapshot items missing from `order_items` are inserted, so a crash after 2-of-3 items leaves 2, and the retry inserts exactly the 3rd (no under-fill, no double stock decrement) |
| 1.2o | Crash after partial order_items insert → retry | final order contains exactly the snapshot items, stock decremented exactly once per item |
| 1.2p | `payment.paid` for an order with empty `items_snapshot` | flagged `payment_conflict` (paid + manual review) — not silently acked |
| 1.2g | Event for unknown payment intent id | `200`, logged `ignored_unknown` |
| 1.2h | `payment.paid` with **amount mismatch** vs order total | order → `payment_conflict` (payment_status `paid`), event `amount_mismatch`, loudly logged; **not** finalized |
| 1.2i | `payment.paid` happy path | order_items inserted (stock decremented by trigger), order → `status='pending'`, `payment_status='paid'`, `gcash_transaction_id=pay_xxx`, `payment_verified_at` set; intent → `succeeded`; event `processed` |
| 1.2j | `payment.paid` when stock ran out (oversell loser) | order → `payment_conflict` (`payment_status='paid'`), event `stock_conflict`; **order never deleted** |
| 1.2k | `payment.paid` arriving **after** the order was expired/cancelled | order → `payment_conflict` ("late payment", refund check flagged) |
| 1.2l | `payment.failed` on awaiting order | order → `cancelled`, `payment_status='failed'`; intent → `failed`; event `processed` |
| 1.2m | `payment.failed` on already-paid order | ignored (`ignored_stale`) |
| 1.2n | Webhook env var `PAYMONGO_WEBHOOK_SECRET` unset | `500`, refuses to process |

### 1.3 get-payment-status

| # | Case | Expect |
|---|---|---|
| 1.3a | No/invalid JWT | `401` |
| 1.3b | User A queries user B's order | `403` |
| 1.3c | Own order, pending | `{ status:'awaiting_payment', payment_status:'pending', paid:false, payment:{status:'pending'} }` |
| 1.3d | Own order, after paid webhook | `{ payment_status:'paid', paid:true }` |
| 1.3e | Expired intent | `payment.status:'expired'`, order `cancelled`/`failed` |

---

## 2. RLS verification (different authenticated accounts)

| # | Case | Expect |
|---|---|---|
| 2.1 | Customer A selects their own `payment_intents` | rows returned |
| 2.2 | Customer B selects A's `payment_intents` (direct API call with B's JWT) | **empty / denied** |
| 2.3 | Authenticated user INSERT/UPDATE/DELETE on `payment_intents` | **denied** (no policies) |
| 2.4 | Authenticated user INSERT/SELECT on `payment_webhook_events` | **denied** |
| 2.5 | Customer attempts DELETE on an `awaiting_payment` order | **denied** — the only customer DELETE policy is `status = 'cancelled'` (verified in `20260805000001_allow_customers_delete_cancelled_orders.sql`), so an in-flight GCash order can't be deleted before the webhook lands |
| 2.6 | `orders` still behaves as before (customers read own, sellers read store's) | unchanged |
| 2.7 | Grant note: if the hosted project doesn't auto-grant new tables (`auto_expose_new_tables` unset in config.toml), the customer-own `payment_intents` SELECT policy is unreachable via REST — the app relies on `get-payment-status` (service role) anyway, so this is a test-expectation alignment, not a security gap |

---

## 3. End-to-end sandbox flows

### 3.1 Happy path
Place GCash order → redirected into (sandbox) GCash auth → pay → webhook fires →
app polls and shows **Order Confirmed** only after `payment_status='paid'` → cart cleared
server-side + locally → seller sees the order in `pending` (pipeline) → stock decremented
exactly once.

### 3.2 Customer abandons the redirect (§7.3)
Close the browser without paying → no webhook → intent `expires_at` passes → pg_cron
sweep flips order to `cancelled`/`failed`. Customer can immediately start a new checkout
for the same items (no stock was held).

### 3.3 Payment fails (§7.3)
GCash rejects / insufficient funds → `payment.failed` webhook → order cancelled/failed,
clear message shown (not "charged?").

### 3.4 Double-checkout race (§7.4)
Two devices / two tabs for the same cart: only one intent is created (active-intent
lookup + unique idempotency key). Only one successful charge possible.

### 3.5 Stock race — last unit (§7.2)
Two customers both reach intent creation with 1 unit left. Both pay in sandbox.
First webhook finalizes (stock decremented). Second webhook → `payment_conflict`,
flagged for manual refund. Verify: exactly one fulfilled order; the other is `paid` +
`payment_conflict` (never silently lost).

### 3.6 App killed mid-flow (§7.8)
Kill the app during the redirect; reopen → deep link / poll path re-queries
`get-payment-status` and shows the truth (paid vs failed vs pending-expired).

### 3.7 Webhook vs app race (§7.5)
Webhook lands before the app returns from the browser: app's poll shows `paid` immediately.
App returns first: poll waits, webhook flips state, poll picks it up. Either order → correct
final state.

### 3.8 Expiry vs late payment
Order expired by sweep, then payment succeeds anyway → `payment_conflict` "late payment"
(manual refund check). No double stock decrement, no orphaned paid order.

---

## 4. Non-functional

| # | Case | Expect |
|---|---|---|
| 4.1 | No secrets in logs | webhook/function logs contain no `sk_…`, `whsk_…`, card/wallet/billing fields; payloads stored redacted |
| 4.2 | Webhook ack semantics | always returns 2xx + JSON so PayMongo stops retrying; genuine failures still logged (`failed`) for investigation |
| 4.3 | Retry storm | 12 retries of the same event → 1 process + 11 no-ops |
| 4.4 | Regression | Cash on Pickup online checkout works exactly as before; POS GCash/cash flows untouched |
| 4.5 | Product-level ratings / reviews | unaffected (no overlapping triggers) |

---

## 5. Live rollout (final step only)

1. All of the above pass on sandbox.
2. Review the webhook handler + migration again (human reviewer).
3. Switch secrets to `sk_live_…` / live webhook secret via `supabase secrets set`
   (never hardcoded) and set the webhook live URL in PayMongo.
4. Register live webhook events (`payment.paid`, `payment.failed`).
5. Recommend a soft rollout (one test store / internal testers first) before enabling
   for all stores — decide with the product owner; a per-store flag system is **not**
   built and not in scope.
6. Confirm `livemode` is recorded correctly in `payment_intents` / `payment_webhook_events`.

---

## 6. Known open items (recorded, not hidden)

- **Flutter wiring** (checkout → intent → system browser → deep link → poll) is the next
  session's work — §9.6 of the architecture doc.
- The exact PayMongo `return_url` parameter placement must be confirmed against a real
  sandbox attach response (code reads it defensively; see §0 note).
- `payment_conflict` orders need a human review workflow (admin list + refund via PayMongo
  dashboard) — not built yet; flagged loudly in DB (`cancellation_reason`/`details`).
- If PayMongo exhausts its 12 retries (e.g. long outage), the event stays `status='failed'`
  and the order stays `awaiting_payment` until the expiry sweep; the captured-charge
  reconciliation is visible in `payment_webhook_events` + `payment_intents` (check
  `payment_intents` where `status='pending'` and `expires_at < now()` and cross-check the
  PayMongo dashboard).
