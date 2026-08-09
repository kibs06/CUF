# Checkout & GCash Payment — Architecture

> **Last updated:** Aug 9, 2026 — **attempt #6 (PayMongo Checkout Sessions online GCash)
> is implemented and wired** (approved migration + 3 Edge Functions + Flutter checkout
> → hosted checkout → poll flow). The gateway-free direct flow (attempt #5) is now
> **dormant/deprecated for the online path** (kept for POS-style reference; POS itself
> is unchanged and out of scope). Online GCash now goes through PayMongo's hosted
> checkout with **server-side, signature-verified webhook** finalization — never
> client-claimed success. See §6 history and §10.
>
> **Purpose:** End-to-end picture of how an order is placed and how GCash fits in,
> accurate to the **current** code. Read this first if you are touching checkout,
> orders, cart, payment, or the POS.
>
> ⚠️ `docs/AI/checkout_screen_and_app_constants.md` is a **stale source dump** from an
> older iteration. Treat this document as the source of truth.

---

## 1. The big picture

SoleVision has **two distinct checkout paths**, each with its own GCash story:

| | **Online (customer)** | **POS (seller, in-store)** |
|---|---|---|
| Entry point | Cart screen → **Check Out** → `CheckoutScreen` | Seller POS → **Checkout sheet** |
| Payment options | **GCash** or **Cash on Pickup** | **GCash** or **Cash** |
| GCash mechanism | **PayMongo Checkout Sessions (hosted page) + verified webhook.** Order is created in `awaiting_payment` (no stock held — defer-until-paid); customer is redirected into GCash to authorize the exact amount (order total + Model B fee); PayMongo's `payment.paid`/`payment.failed` webhook (HMAC-verified) finalizes the order. See §10 | **Static seller QR** — customer scans seller's uploaded GCash QR; seller confirms receipt manually |
| Money movement | Customer's GCash → **PayMongo** → platform/seller settlement (PayMongo fee passed to customer as a disclosed Model B surcharge) | Peer-to-peer, no gateway |
| Order `source` | `online` | `pos` |
| Order `status` on creation | `awaiting_payment` → `pending` after webhook confirms payment | `received` |
| Order `payment_status` | `pending` → `paid` (**only the signature-verified webhook** may set it) / `failed` on fail/expire | `paid` (cash) / `pending` → `paid` (seller taps "Payment Received") |

> **The three "pending"-meanings are cleanly separated** (documented, not assumed):
>
> 1. `orders.status = 'awaiting_payment'` — **online GCash (PayMongo)**: order created,
>    payment not yet confirmed, **no stock held** (defer-until-paid). The webhook moves
>    it to `pending` (paid) or `cancelled` (failed/expired).
> 2. `orders.payment_status = 'pending'` — payment not yet confirmed. Used by online
>    GCash while `status='awaiting_payment'`, and POS GCash between order creation and
>    the seller tapping "Payment Received".
> 3. `orders.status = 'pending'` — **paid and in the normal fulfillment pipeline**,
>    awaiting the seller's fulfillment actions (preparing → ready → delivered). Online
>    orders only reach this state **after** the webhook confirms payment.
>
> There is no longer any path where an online order sits in `status='pending'` unpaid.
>
> (The attempt-#5 `awaiting_payment_confirmation` status still exists in the DB and UI
> as a dormant path for legacy orders — see §9. It is not produced by the current online
> checkout.)

Key files: `lib/screens/customer/cart_screen.dart`, `lib/screens/customer/checkout_screen.dart`,
`lib/screens/customer/gcash_payment_screen.dart` (new, attempt #6),
`lib/screens/customer/tracking_screen.dart`, `lib/services/gcash_payment_service.dart` (new),
`lib/services/deep_link_service.dart` (new), `lib/screens/seller/pos_screen.dart`,
`lib/services/supabase_service.dart` (`createOrder`), `lib/providers/order_provider.dart`,
`lib/providers/cart_provider.dart`, plus the attempt-#6 migration (§10) and the three
Edge Functions `create-gcash-payment-intent` / `gcash-webhook` / `get-payment-status`.

---

## 2. Online checkout flow (customer) — current app behavior

```
CartScreen (sticky bar)
  │  user selects items → total shown (subtotal + ₱100 delivery)
  │  "Check Out" → Navigator.push(CheckoutScreen)          [cart_screen.dart ~L719]
  ▼
CheckoutScreen — 2 internal steps (_checkoutStep)
  ┌─ Step 0 "Checkout Details" ─────────────────────────────────────┐
  │ • Validation banners (out of stock / insufficient stock / price │
  │   changed) from cart.validateForCheckout() — warns, never       │
  │   auto-removes; blocks submit while invalid                     │
  │ • Order Summary (selected items + qty + line totals)            │
  │ • Deliver To — address book picker (AddressProvider); auto-     │
  │   selects default address; REQUIRED to place order              │
  │ • Payment Method — radio: "GCash" / "Cash on Pickup"            │
  │ • Price breakdown — Subtotal, ₱100 Delivery Fee, GCash Fee      │
  │   (Model B, server-computed via get_gcash_fee, own line item),  │
  │   Estimated delivery date, Total (incl. fee when GCash)         │
  │ • "Complete Order" (SolePrimaryButton)                          │
  └─────────────────────────────────────────────────────────────────┘
  │  _submitCheckout():
  │    GCash        → GcashPaymentService.createIntent(...) → Edge
  │                   Function create-gcash-payment-intent → order in
  │                   awaiting_payment (NO stock held — defer-until-
  │                   paid) + PayMongo hosted Checkout Session,
  │                   cart cleared, pushReplacement → GcashPaymentScreen
  │                   ⚠️ 409 (one-pending cap) → RESOLUTION DIALOG:
  │                     "Complete Payment" (resume existing checkout)
  │                     or "Cancel Pending" (customer RPC → auto-retry)
  │    Cash on Pickup → orderProvider.placeOrder(...) → createOrder()
  ▼
  ┌─ GcashPaymentScreen (GCash only, attempt #6) ───────────────────┐
  │ Amount-to-pay card (items+delivery, GCash Fee line, Total Due)   │
  │ 15-min countdown (expires_at from the intent)                    │
  │ "Open GCash" → PayMongo hosted checkout URL in the SYSTEM       │
  │   browser (never an in-app webview — GCash app handoff needs     │
  │   the gcash:// custom scheme)                                    │
  │ Polls get-payment-status every 3s — the deep-link return only    │
  │   triggers a poll; it NEVER marks anything paid.                 │
  │ Terminal states: paid (verified) / failed / expired / cancelled  │
  │   / payment_conflict — honest, no "was I charged?" guessing      │
  └─────────────────────────────────────────────────────────────────┘
  ▼
OrderTrackingScreen — status 'awaiting_payment' shows its own banner +
  countdown + "Complete Payment" resume (back to GcashPaymentScreen);
  'payment_conflict' shows a needs-review banner. Deep links
  (solvision://checkout/gcash/*) resume the pending checkout screen.
```

### Cash on Pickup path (unchanged)

`createOrder(orderData)` in `supabase_service.dart` remains the single order-creation
entry point for **cash-on-pickup only**. `payment_method` is normalized
(`'GCash' → 'gcash'`, `'card'`, else `'cash'`). It inserts the `orders` row +
`order_items` (non-atomic; orphaned order is deleted + stock errors surfaced on
item-insert failure). The GCash branch no longer reaches `createOrder` — the fake-paid
non-cash branch (`payment_status: method == 'cash' ? 'unpaid' : 'paid'`) is now
unreachable from the app UI.

---

## 3. POS checkout flow (seller, in-store) — unchanged, out of scope

Inside `lib/screens/seller/pos_screen.dart` → `_CheckoutSheet` (method `Cash` | `GCash`):

```
Seller taps GCash
  │  _hasGcashQr = store.gcash_qr_url not empty
  ▼
_startGcashPayment():
  1. _createPendingOrder()  → status='received', payment_status='pending',
     source='pos', method='gcash'
  2. Display store's uploaded static QR + gcash_number / gcash_account_name
  3. Seller watches customer scan & pay with GCash app
  4. "Payment Received" → _confirmGcashPayment(): payment_status='paid'
     (+ optional gcash_reference_number typed by seller), then order_items
  │  (sheet closed before confirm → pending order cleaned up)
```

The QR is the seller's personal "Receive Money" QR, uploaded once via
`lib/screens/seller/gcash_payment_settings_screen.dart`. No gateway; confirmation is
manual by the seller. **This flow is untouched by attempt #5.**

---

## 4. Online GCash today (attempt #6 — PayMongo Checkout Sessions, verified webhook)

- **Server-side** (§10): approved migration `20260809000000_revive_paymongo_online_gcash.sql`
  (Model B fee config + `get_gcash_fee`/`set_payment_fee_config` RPCs, orders fee columns,
  `payment_intents.checkout_session_id`/fee columns, expiry sweep re-ensured) + three
  Edge Functions: `create-gcash-payment-intent` (server-side total + fee recompute,
  idempotent, 15-min expiry), `gcash-webhook` (**HMAC-SHA256 signature-verified**,
  idempotent on `paymongo_event_id`, fee-aware amount check, defer-until-paid
  materialization, `payment_conflict` on mismatch), `get-payment-status` (authenticated
  poll endpoint, enforces expiry).
- **Flutter**: `checkout_screen.dart` GCash path calls `create-gcash-payment-intent` and
  hands off to `gcash_payment_screen.dart` (amount + fee breakdown, Open GCash in the
  system browser, 15-min countdown, 3s status polling, honest terminal states).
  `tracking_screen.dart` renders `awaiting_payment` + `payment_conflict`;
  `sole_status_chip.dart` styles both. `deep_link_service.dart` + `main.dart`
  `DeepLinkHost` handle `solvision://checkout/gcash/*` returns (informational only).
- The attempt-#5 gateway-free direct flow (static QR + proof submission + seller queue)
  is **dormant/deprecated for the online path** — kept for legacy orders and reference
  (§9). The POS static-QR flow is **untouched** (out of scope).
- The legacy fake-paid path (online GCash → instant `paid` via `createOrder`) is now
  **unreachable from the app UI**; `createOrder` still serves cash-on-pickup only.

---

## 5. Orders schema (checkout-relevant columns)

```sql
orders (
  id                             UUID PK       -- ⚠️ LIVE DB: UUID. schema.sql says BIGINT — schema.sql is stale
  customer_id                    UUID → profiles(id)
  store_id                       UUID → stores(id)
  status                         TEXT  -- ONLINE GCash (#6): awaiting_payment → pending (webhook paid)
                                            --   / cancelled (failed | expired | customer-cancel)
                                            --   / payment_conflict (money captured, needs review)
                                            -- LEGACY (#5): awaiting_payment_confirmation → pending (seller confirms)
                                            -- CASH online / confirmed: pending → preparing → ready →
                                            --   delivered → received; + placed, cancelled,
                                            --   cancellation_requested
  total_amount                   NUMERIC -- seller revenue basis (products + delivery; fee NOT included)
  payment_method                 TEXT  -- 'gcash' | 'cash' | 'card' (normalized)
  payment_status                 TEXT  -- CHECK IN ('paid','unpaid','pending','failed')
  fulfillment                    TEXT  -- always 'pickup' in practice
  notes                          TEXT  -- delivery address text (online)
  shipping_address               JSONB -- address snapshot (online)
  source                         TEXT  -- 'online' | 'pos'
  amount_tendered / change_amount NUMERIC -- POS cash
  payment_confirmation_deadline  TIMESTAMPTZ -- LEGACY (#5) only
  gcash_reference_number         TEXT  -- POS manual flow only (seller-typed ref #)
  gcash_transaction_id           TEXT  -- PayMongo payment id, recorded by the #6 webhook on payment.paid
  payment_verified_at            TIMESTAMPTZ -- set by the #6 webhook on payment.paid
  gcash_fee_amount / _rate_bps / _vat_bps -- NEW (#6): Model B surcharge snapshot per order
  created_at                     TIMESTAMPTZ
)
-- order_items(order_id, product_id, size, quantity, unit_price) — stock is decremented
--   by trigger `decrement_inventory_on_order` on insert; raises 'Insufficient stock' (P0001)
--   ONLINE GCash (#6): order_items are NOT inserted at creation (defer-until-paid) — the
--   webhook materializes them from payment_intents.items_snapshot on payment.paid, so
--   stock decrements exactly once, only after verified payment.
--   LEGACY (#5): inserted at creation (stock reserved); released exactly-once on reject/expire.
```

Attempt-#6 payment tables (revived from attempt #4 by `20260809000000_revive_paymongo_online_gcash.sql`):

| Table | Purpose | RLS |
|---|---|---|
| `payment_intents` | one per online GCash checkout: `order_id`, `paymongo_payment_intent_id` (unique), `checkout_session_id` (unique, NEW #6), `client_key`, `amount` (charged = total + fee), `fee_amount`/`fee_rate_bps` (NEW #6), `items_snapshot` (defer-until-paid), `status` pending/succeeded/failed/expired/cancelled, `expires_at` (15 min), `customer_id`; partial unique on `customer_id WHERE status='pending'` = the one-pending cap | SELECT own-customer only; **no client writes** |
| `payment_webhook_events` | append-only audit + idempotency gate: `paymongo_event_id` **UNIQUE** (the idempotency key), `event_type`, redacted payload, `order_id`, `processed_at` | **no client policies** — service-role inserts only |
| `payment_fee_config` | singleton (id=1): `rate_bps` (seeded 223 = 2.23%), `vat_bps` (1200 = 12%), `active`, `updated_by/at` | SELECT for any signed-in user; **no write policies** — `set_payment_fee_config` admin RPC only |

New tables (attempt #5 — `20260808200000_add_direct_gcash_online_checkout.sql`):

| Table | Purpose | RLS |
|---|---|---|
| `gcash_payment_proofs` | one proof per order: `reference_number` **platform-wide UNIQUE** (12–13 digit CHECK), `screenshot_url NOT NULL` (required), `submitted_by`, `submitted_at` | SELECT own-order-customer or own-store-seller only; **no write policies** (RPC-only) |
| `order_payment_events` | append-only audit log: `event_type` `created` / `proof_submitted` / `confirmed` / `rejected` / `expired`, `actor_id`, `notes` (e.g. rejection reason), `created_at` | SELECT own-order-customer or own-store-seller; **no insert policies** |
| storage bucket `payment-proofs` (private) | proof screenshots, path `{order_id}/{filename}` | INSERT/UPDATE/DELETE by the order's customer; SELECT by the order's customer or its store's seller; app reads via **signed URLs** |

### Orders UPDATE policy — tightened (attempt #5)

The old policy let *any* user with `role='seller'` update *any* order row (a seller
could flip `payment_status='paid'` cross-store straight from the client). It is now
store-scoped: `EXISTS (SELECT 1 FROM stores WHERE id = orders.store_id AND owner_id = auth.uid())`
or `role='admin'`. All seller flows only touch their own store's orders; the customer
confirm-receipt path goes through RPC/trigger-adjacent code and the `tracking_screen`
receipt flow — verified no regression.

---

## 6. GCash history — why the current design is what it is

| # | Approach | Date | Outcome |
|---|---|---|---|
| 1 | PayMongo **Sources** API + QR image | ~Jul 29 | ❌ GCash scanner rejected non-QR-Ph code |
| 2 | PayMongo **QR Ph** Payment Intents + webhook | Jul 30 | ❌ Abandoned — webhook signature verification was a **stub**, inventory timing bugs |
| 3 | Manual static QR (POS only) | Aug 6 | ✅ Live for POS |
| 4 | PayMongo **Payment Intents** + `gcash` e-wallet redirect + verified webhook (online) | Aug 8 | ❌ **Built then replaced before production** — hit "payment provider unavailable" in practice; abandoned in favor of #5 |
| 5 | **Gateway-free direct GCash (online): static seller QR + proof submission + seller confirmation, mirroring POS** | Aug 8 | ✅ Implemented and shipped — **now dormant/deprecated for the online path** (kept for legacy orders; POS static QR remains live and is untouched) |
| **6 (current)** | **PayMongo Checkout Sessions (hosted page) + HMAC-verified webhook, Model B fee passed to customer** | **Aug 9** | ✅ **Implemented** — approved migration + 3 Edge Functions + Flutter flow (checkout → hosted GCash → poll). **Sandbox verification pending** (needs PayMongo test keys + a registered webhook endpoint — see §10.8) |

Attempt #6 **revives and extends** attempt #4's dormant assets: `payment_intents` /
`payment_webhook_events` tables and the `create-gcash-payment-intent` /
`gcash-webhook` / `get-payment-status` Edge Functions were inspected, hardened, and
re-purposed for the Checkout Sessions API (the manual Payment-Intents + attach flow was
replaced by a hosted checkout, per PayMongo's current recommendation). The dormant
`gcash_transaction_id` / `payment_verified_at` orders columns are reused by the webhook
(recorded on `payment.paid`). `docs/to be continue/GCASH_PAYMONGO_ARCHITECTURE.md`
documents attempt #2 (reference only).

---

## 7. Known quirks & honest gaps

- **Attempt-#5 direct-flow quirks** (below) apply only to legacy `awaiting_payment_confirmation`
  orders — the current online GCash path is attempt #6 (§10), which has its own gaps.
- **Attempt #6 — payment infra** (see §10 for the full model): PayMongo fees are passed
  to the customer (Model B surcharge, server-computed, disclosed as its own line item);
  the intent stores no stock (defer-until-paid); orders are finalized **only** by the
  signature-verified webhook. **Sandbox verification is still pending** — the three Edge
  Functions have not yet been exercised against PayMongo test keys or a real hosted
  checkout (needs a registered webhook endpoint + `whsk_test_…` secret). Until then the
  migration + functions are code-reviewed and typechecked, not live-tested.
- **One pending Checkout Session per customer** — enforced by the attempt-#4 partial
  unique index on `payment_intents(customer_id) WHERE status='pending'` (atomic; a
  second checkout fails → the edge function returns 409). The checkout UI maps this to
  an actionable dialog: **Complete Payment** (resume the existing checkout's payment
  screen) or **Cancel Pending** (customer RPC → frees the cap → auto-retry).
- **Expiry**: 15 minutes (confirmed with the human). Enforced by the pg_cron sweep
  (every 5 min) **and** by `get-payment-status` on read (mirrors the sweep's UPDATE), so
  the app's countdown reaching zero is authoritative immediately.
- **Cart keeps the items while payment is awaiting** (user-requested). Items are NOT
  removed at intent creation — they stay visible in My Cart while the order is
  `awaiting_payment` (no stock is held, so nothing to lose; the customer can cancel
  or retry freely). The payment screen removes exactly the purchased lines from the
  cart (quantity-aware) only once the server-confirmed status shows paid/conflict and
  the webhook has materialized `order_items`. Items added to the cart while payment
  was pending are preserved.
- **Idempotency**: webhook processing is keyed on the unique `paymongo_event_id`
  (second deliveries no-op); intent creation dedupes server-side on the customer's
  pending intent + the client's idempotency key (stable per submission — retries reuse
  it, only reset after the checkout resolves/cancels).
- **Amount integrity**: `create-gcash-payment-intent` recomputes prices + Model B fee
  from the DB; the webhook re-verifies the charged amount against the stored intent and
  flags `payment_conflict` (terminal, manual review) on mismatch — a paid order is
  never silently accepted or deleted.
- Online cash-on-pickup orders stay `payment_status='unpaid'` until the seller marks them paid.
- Cash-on-pickup order placement is not wrapped in a DB transaction (two-step insert with
  manual rollback of the orphaned order row) — unchanged.
- **Legacy (§9) quirks kept for reference**: screenshot-required proof submission;
  platform-wide reference-number uniqueness; 30-min → +2h deadline on proof submission;
  stock reserved at creation and released exactly once on reject/expire; the seller FCM
  push gap (in-app realtime badge works, FCM push not fired by the RPC).

---

## 8. File map

| File | Role |
|---|---|
| `lib/screens/customer/cart_screen.dart` | Cart, selection, sticky Check Out bar |
| `lib/screens/customer/checkout_screen.dart` | Checkout details; GCash branch → `create-gcash-payment-intent` → GcashPaymentScreen; Model B fee line |
| `lib/screens/customer/gcash_payment_screen.dart` | **NEW (attempt #6)** — amount+fee card, Open GCash (system browser), 15-min countdown, 3s poll, terminal states |
| `lib/screens/customer/gcash_pay_screen.dart` | **DORMANT (attempt #5)** — QR + proof form, kept for legacy orders |
| `lib/screens/customer/tracking_screen.dart` | **UPDATED** — `awaiting_payment` + `payment_conflict` banners, PayMongo resume + countdown |
| `lib/screens/seller/pos_screen.dart` | POS `_CheckoutSheet` — Cash + static-QR GCash (**untouched**) |
| `lib/screens/seller/gcash_payment_queue_screen.dart` | **DORMANT (attempt #5)** — seller Confirm / Reject queue, kept for legacy orders |
| `lib/screens/seller/seller_dashboard_screen.dart` | **UPDATED** — "Payments to confirm" card (attempt-#5 legacy path) |
| `lib/screens/seller/gcash_payment_settings_screen.dart` | Seller uploads GCash QR + number/name (POS still uses this) |
| `lib/widgets/sole_status_chip.dart` | **UPDATED** — styles `awaiting_payment`, `payment_conflict`, `awaiting_payment_confirmation` |
| `lib/services/direct_gcash_service.dart` | **DORMANT (attempt #5)** — RPC wrappers for the legacy direct flow |
| `lib/services/gcash_payment_service.dart` | **NEW (attempt #6)** — intent create / status poll / cancel / fee fetch, error mapping |
| `lib/services/deep_link_service.dart` | **NEW (attempt #6)** — `solvision://checkout/gcash/*` stream + matcher |
| `lib/services/supabase_service.dart` | `createOrder()` (cash-on-pickup only), payment normalizer |
| `lib/providers/cart_provider.dart` | Hybrid cart, selected items, totals |
| `lib/providers/order_provider.dart` | `placeOrder()` → createOrder; stock errors |
| `lib/main.dart` | **UPDATED** — `DeepLinkHost` cold-start resume + navigator key |
| `supabase/migrations/20260809000000_revive_paymongo_online_gcash.sql` | **NEW (attempt #6)** — fee config + RPCs + orders/`payment_intents` columns + sweep re-ensure |
| `supabase/migrations/20260808200000/20260808210000_…direct_gcash…` | **DORMANT (attempt #5)** — kept; legacy `awaiting_payment_confirmation` orders |
| `supabase/functions/create-gcash-payment-intent` | **WIRED (attempt #6)** — server-side total+fee, idempotent, 15-min expiry |
| `supabase/functions/gcash-webhook` | **WIRED (attempt #6)** — HMAC-verified, idempotent, fee-aware, finalizes orders |
| `supabase/functions/get-payment-status` | **WIRED (attempt #6)** — authenticated poll + expiry enforcement |
| `supabase/functions/_shared/paymongo.ts` | **NEW (attempt #6)** — Checkout Sessions helper + signature verify + event parsing |
| `docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN.md` | Test cases for attempt #6 (sandbox-first) |
| `docs/AI/ONLINE_GCASH_TEST_PLAN.md` | Test cases for the (legacy) direct flow |

---

## 9. NEW — Gateway-free direct GCash online flow (attempt #5)

### 9.1 Flow

```
CheckoutScreen (GCash selected)
  ▼
1. RPC create_gcash_checkout(p_items, p_delivery_address, p_shipping_address)
     (SECURITY DEFINER; JWT required, must be a customer)
   Server:  revalidates stock + recomputes total from CURRENT product prices
            + ₱100 delivery (NEVER trusts the client total) →
            creates orders row (status='awaiting_payment_confirmation',
            payment_status='pending', payment_confirmation_deadline=now()+30min) →
            inserts order_items (existing trigger decrements stock atomically;
            oversell → P0001 → full rollback) →
            logs order_payment_events 'created' →
            returns { order_id, total_amount, deadline,
                      store: { gcash_qr_url, gcash_number, gcash_account_name } }
   One-open-order cap: a second checkout for the same customer hits the partial
   unique index → 23505 → friendly error. Retrying a paid/dead order is fine.
  ▼
2. App clears the cart, pushReplacement → GcashPayScreen
   (QR + number + name + exact amount + 30-min countdown)
   Customer pays the seller DIRECTLY via their own GCash app (outside the app).
  ▼
3. RPC submit_gcash_proof(p_order_id, p_reference_number, p_screenshot_url)
     (customer who owns the order only)
   Checks: order exists + status='awaiting_payment_confirmation' + owned by caller +
     deadline not passed + ref normalized to 12–13 digits + platform-wide UNIQUE +
     screenshot path under {order_id}/ folder →
     inserts gcash_payment_proofs (one per order) →
     EXTENDS deadline to now()+2h (decision: a paid order never expires mid-proof) →
     logs 'proof_submitted' → inserts seller_notifications row (in-app realtime badge)
  ▼
4. Seller dashboard card "Payments to confirm" (live count, 30s poll + sweep)
   → GcashPaymentQueueScreen: proof ref + signed-URL screenshot + order details
   Seller taps:
     "Confirm Payment Received" → RPC confirm_gcash_payment(p_order_id)
         (store OWNER only — explicit ownership check + RLS) →
         guarded transition to status='pending', payment_status='paid' (no stock
         change — already reserved) → logs 'confirmed' → customer notification
     "Reject / Not Received" (reason) → RPC reject_gcash_payment(p_order_id, p_reason)
         (store owner only) → cancels order → releases stock EXACTLY ONCE (guarded
         DELETE order_items + re-increment, serialized FOR UPDATE) → logs 'rejected'
         with reason → customer notification with reason
  ▼
5. No action before the deadline → expire_overdue_gcash_orders()
     (pg_cron job + opportunistic app calls; idempotent)
     cancels overdue orders → releases stock exactly-once → logs 'expired' →
     notifies customer to retry checkout. Seller can no longer confirm an expired order.

Optional (any time while still awaiting, BEFORE proof is submitted):
     RPC cancel_my_pending_gcash_checkout (customer-owned, guarded) →
     same cancellation path as reject (stock released exactly once,
     'cancelled_by_customer' logged, notification sent) → frees the
     one-open-order cap so the customer can check out again immediately.
     Blocked server-side once proof is submitted — the money may already
     have moved, so the store must confirm or reject it.
```

### 9.2 The state machine (brief §5.1 — explicit)

```
                        ┌────────────────────────────────────────────┐
   checkout            │   awaiting_payment_confirmation             │
 create_gcash_checkout │   (payment_status='pending',               │
        ──────────────►│    payment_confirmation_deadline set,      │
                        │    stock RESERVED)                          │
                        └──────────────┬──────────────┬──────────────┘
                                       │              │
               seller Confirm          │              │  no action by deadline
               (confirm_gcash_payment) │              │  (expire_overdue_gcash_orders)
                                       ▼              ▼
   status='pending' (paid,        status='cancelled'    status='cancelled'
   payment_status='paid')         rejected by seller    expired
   → normal fulfillment           (stock released)      (stock released)
   pipeline: preparing →          → customer notified   → customer notified,
   ready → delivered → received   with reason             retry checkout
```

Guarantees:
- Every order entering `awaiting_payment_confirmation` ends up **exactly one** of:
  confirmed (`pending`), rejected (`cancelled`), expired (`cancelled`), or
  cancelled-by-customer (`cancelled`) — never stuck.
- **Customer self-cancel**: while no proof is submitted, the customer can cancel
  their own pending order (`cancel_my_pending_gcash_checkout`, ownership + no-proof
  guarded) → stock released exactly once, `cancelled_by_customer` logged, customer
  notified → the one-open-order cap is freed so they can check out again. Blocked
  once proof is submitted (store must confirm/reject — money may have moved).
- **Confirm and reject race** (double-tap / two devices): the guarded
  `UPDATE … WHERE status='awaiting_payment_confirmation'` transitions atomically —
  only the first wins; the loser no-ops.
- **Stock moves exactly once** (reserved at creation by the existing decrement trigger;
  released on reject/expire by a guarded exactly-once release; confirm touches no stock).
- **Ref reuse** is impossible platform-wide (UNIQUE); **cross-store seller actions** are
  impossible (ownership check inside the RPC + store-scoped UPDATE policy).
- **Disputes** ("I paid but seller says no") are reconstructible from the append-only
  `order_payment_events` log (actor + timestamp + notes for every transition).

### 9.3 Security posture (brief §3 — all implemented)

1. **Server is the only source of truth for `payment_status`** — the client role has no
   INSERT/UPDATE policy on `gcash_payment_proofs` or `order_payment_events`, and the
   tightened orders UPDATE policy + RPC ownership checks prevent any client-side
   `paid` write. Only `confirm_gcash_payment` (store owner) sets `paid`.
2. **Reference-number reuse detection** — platform-wide UNIQUE on `gcash_payment_proofs.reference_number`
   (12–13 digit CHECK, normalized) — one real payment can prove at most one order.
3. **Ownership checks on every action** — submit-proof requires the order's customer;
   confirm/reject require the order's store owner (`stores.owner_id = auth.uid()`),
   verified in the RPC **and** by RLS, not just hidden in the UI.
4. **Abuse prevention** — one open `awaiting_payment_confirmation` order per customer
   (atomic partial unique index); repeated-proof submissions are impossible (one proof
   per order, `order_id UNIQUE`).
5. **Audit trail** — `order_payment_events` records every transition with actor +
   timestamp + notes; append-only by construction (no client insert policies).
6. **RLS on all new tables/columns** — customers see only their own orders/proofs;
   sellers only their own store's; nobody writes payment state from the client role.
7. **Screenshot privacy** — `payment-proofs` bucket is **private**; reads go through
   signed URLs scoped to the order's customer or its store's seller.
8. **Stock reservation always resolves** — the expiry sweep (pg_cron + opportunistic)
   guarantees no order holds stock forever.
9. **No silent trust escalation** — there is deliberately **no** auto-confirm logic;
   the seller's manual confirmation is the security control.

### 9.4 Error/terminal states

| Path | orders.status | payment_status | Stock |
|---|---|---|---|
| Checkout created (GCash) | `awaiting_payment_confirmation` | `pending` | reserved |
| Proof submitted | unchanged | `pending` | reserved (deadline +2h) |
| Seller confirms | `pending` | `paid` | reserved (normal pipeline) |
| Seller rejects | `cancelled` | `pending` | **released exactly once** |
| Expiry sweep (no action) | `cancelled` | `pending` | **released exactly once** |
| Oversell at checkout (P0001) | (rollback — no row) | — | untouched |

### 9.5 RPC reference

| Function | Caller | Signature |
|---|---|---|
| `create_gcash_checkout` | customer | `(p_items jsonb, p_delivery_address text, p_shipping_address jsonb) → jsonb` |
| `submit_gcash_proof` | order's customer | `(p_order_id uuid, p_reference_number text, p_screenshot_url text) → jsonb` |
| `confirm_gcash_payment` | order's store owner | `(p_order_id uuid) → jsonb` |
| `reject_gcash_payment` | order's store owner | `(p_order_id uuid, p_reason text) → jsonb` |
| `cancel_my_pending_gcash_checkout` | order's customer (no proof yet) | `(p_order_id uuid) → boolean` |
| `expire_overdue_gcash_orders` | any auth / pg_cron | `() → int` (count expired) |

### 9.6 Apply + verify

```bash
supabase db push        # applies 20260808200000 then 20260808210000
```

Verification queries live at the bottom of each migration; the manual test plan
(happy path → reject → expire → ref-reuse → cross-account denial) is in
`docs/AI/ONLINE_GCASH_TEST_PLAN.md`. No secrets, env vars, or Edge Function deploys are
required for the online GCash flow — there is no gateway.

### 9.7 Flutter wiring (done Aug 8, 2026)

- **`lib/services/direct_gcash_service.dart`** (new) — typed wrappers around the five
  RPCs with friendly error mapping (P0001 → stock message, 23505 → "already have a
  pending GCash order", 42501 → permission), screenshot upload to the private
  `payment-proofs` bucket, and signed-URL reads.
- **`checkout_screen.dart`** — GCash radio calls `create_gcash_checkout` (server
  recomputes the total; client sends only product/size/quantity), clears the cart, and
  `pushReplacement`es to `GcashPayScreen`. Cash on Pickup is unchanged. The entire
  PayMongo `app_links` / `launchUrl` / polling machinery was **removed**.
- **`gcash_pay_screen.dart`** (new) — QR + number + account name + exact amount +
  30-min countdown; proof form (ref required + screenshot required via `image_picker`);
  submit → `submit_gcash_proof`; submitted state with a "Track Order" escape; orphaned
  screenshots deleted on failed submits.
- **`seller_dashboard_screen.dart`** — self-contained "Payments to confirm" card with a
  live count (30 s poll) that also fires the opportunistic expiry sweep; taps through to
  the queue screen.
- **`gcash_payment_queue_screen.dart`** (new) — list of orders awaiting confirmation
  with the submitted ref + signed-URL screenshot, Confirm and Reject-with-reason
  actions, ownership enforced server-side.
- **`tracking_screen.dart`** — renders `awaiting_payment_confirmation` as its own state:
  distinct banner + countdown, resume-payment button (back to `GcashPayScreen`) when no
  proof exists yet, and an opportunistic expiry sweep call so stale orders resolve
  without waiting for cron.
- **`sole_status_chip.dart`** — label/color for the new status.
- **`pos_screen.dart`** — untouched.

---

## 10. NEW — PayMongo Checkout Sessions online GCash (attempt #6, Aug 9 2026)

> Decisions confirmed with the human: **build PayMongo** (replacing the gateway-free
> online flow), **Model B** fee (surcharge passed to the customer), **system-browser
> redirect** (recommended — in-app WebViews don't intercept the `gcash://` handoff),
> **15-minute expiry**. API: **Checkout Sessions** (hosted page — PayMongo's current
> recommendation; the manual Payment-Intents + attach flow from attempt #4 is what hit
> "payment provider unavailable" and is not reused).

### 10.1 Flow

```
CheckoutScreen (GCash selected)
  ▼
1. Edge Function create-gcash-payment-intent (JWT required, customer only)
   Input:  { idempotency_key, items: [{product_id, size, quantity}],
            delivery_address, shipping_address }   ← NO client total
   Server: recomputes total from CURRENT product prices + ₱100 delivery →
           computes Model B fee from payment_fee_config (rate + VAT) →
           creates orders row (status='awaiting_payment', payment_status='pending',
             NO stock touched — defer-until-paid) → creates payment_intents row
             (paymongo_payment_intent_id, client_key, amount=total+fee,
              fee_amount, checkout_session_id, expires_at=now()+15min) →
           calls PayMongo Checkout Sessions API (billing amount, description,
             payment_method_types ['gcash'], success_url/cancel_url deep links
             solvision://checkout/gcash/success|failed) →
           returns { order_id, checkout_url, client_key, amount, fee_amount,
                     expires_at }
   Idempotency: same idempotency_key OR an existing pending intent for the
     customer → returns the existing checkout (already_exists=true) instead of
     duplicating; the one-pending-per-customer partial unique index enforces it
     atomically (conflict → 409).
  ▼
2. App clears the cart, pushReplacement → GcashPaymentScreen
   (amount card incl. fee line, 15-min countdown, "Open GCash")
   "Open GCash" → launchUrl(checkout_url, externalApplication) → SYSTEM browser.
   PayMongo's hosted page → GCash app handoff → customer authorizes the exact
   amount → redirected back to solvision://checkout/gcash/success|failed.
  ▼
3. Return deep link (informational ONLY): DeepLinkHost / GcashPaymentScreen
   listener triggers an immediate poll of get-payment-status. The app NEVER
   marks anything paid from the redirect.
   Meanwhile the screen polls get-payment-status every 3s (also on app resume).
  ▼
4. Edge Function gcash-webhook (public, but every request is signature-verified)
   PayMongo sends payment.paid / payment.failed / checkout.session.expired.
   Handler: verify Paymongo-Signature (HMAC-SHA256 over '<t>.<raw body>',
   timing-safe compare, 10-min replay guard, no bypass flag) → idempotency gate
   (UNIQUE paymongo_event_id in payment_webhook_events — second delivery no-ops)
   → lookup order by paymongo_payment_intent_id / checkout_session_id →
   payment.paid: re-verify amount vs stored intent (mismatch → payment_conflict
     terminal, manual review — never silently accepted) → materialize order_items
     from items_snapshot (defer-until-paid: stock decremented HERE, once) →
     status='pending', payment_status='paid', gcash_transaction_id +
     payment_verified_at recorded → seller + customer notifications.
   payment.failed / session expired: status='cancelled', payment_status='failed',
     cancellation_reason set → notification. (No stock to release — none held.)
  ▼
5. OrderTrackingScreen shows paid/pending pipeline — only after the webhook's
   payment.paid has been verified server-side.

Customer self-service (any time while still awaiting):
  RPC cancel_my_pending_payment_intent (customer-owned, guarded) → cancels the
  order + marks the intent cancelled → frees the one-pending cap → the checkout
  can be retried immediately.

Expiry (no payment, no cancel): 15-min window enforced by the pg_cron sweep
  (every 5 min) AND by get-payment-status on read (mirrors the sweep's UPDATE,
  idempotent) → order cancelled with 'Payment session expired', intent 'expired',
  audit row appended. No stock was ever held.
```

### 10.2 State machine

```
                    ┌─────────────────────────────────────────────┐
   checkout         │  awaiting_payment (payment_status='pending',│
 create-intent ────►│  NO stock held, expires_at=+15min)          │
                    └───────┬──────────────┬─────────────┬───────┘
                            │              │             │
          webhook           │   webhook    │  customer   │  expiry
          payment.paid      │   failed/    │  cancel RPC │  (sweep + poll)
                            │   expired    │             │
                            ▼              ▼             ▼
   status='pending'    status='cancelled'  status='cancelled'  status='cancelled'
   payment_status=     payment_status=     (intent cancelled)  'Payment session
   'paid'              'failed'                                 expired', intent
   → order_items       (no stock held)     → cap freed          'expired'
   materialized HERE                                             → cap freed
   → normal pipeline

   amount mismatch on payment.paid → status='payment_conflict'
   (payment_status='paid', manual review — never silently deleted)
```

Guarantees:
- Every `awaiting_payment` order resolves to exactly one of: `pending` (paid),
  `cancelled` (failed/expired/customer-cancelled), or `payment_conflict` (needs
  review) — never stuck, never silently deleted after money moved.
- **Stock decrements exactly once, only after verified payment** (order_items
  materialized in the webhook from `items_snapshot`; oversell → P0001 →
  `payment_conflict` for manual resolution). This is the anti-pattern that killed
  attempt #2 — deliberately sidestepped by defer-until-paid.
- **No double-fulfillment**: idempotency gate on `paymongo_event_id` (unique),
  guarded `UPDATE … WHERE status='awaiting_payment'` transitions, and the
  one-pending-per-customer index on intent creation.
- **No silent acceptance**: every `payment.paid` re-verifies the charged amount
  against the stored intent; mismatches go to `payment_conflict`.

### 10.3 Fee model (Model B — surcharge to customer)

- Rate lives in `payment_fee_config` (singleton row; seeded 223 bps = 2.23% + 12%
  VAT, editable via the `set_payment_fee_config` admin RPC — data, not code).
- `get_gcash_fee(p_subtotal)` RPC returns `{ base, rate_bps, fee_amount,
  total_charged }` for the checkout display; formula
  `charged = ceil_to_cent(total / (1 − r_total))` with
  `r_total = (rate_bps/10000) * (1 + vat_bps/10000)` — the surcharge always covers
  PayMongo's fee, and is **disclosed as its own line item** (never bundled into
  delivery). The intent function recomputes authoritatively; `orders.gcash_fee_amount`
  snapshots it per order so seller revenue queries on `total_amount` stay honest.

### 10.4 Security posture

1. **Server is the only source of truth** — the client role has no write path to
   `payment_status`; only the webhook (service role) sets `paid`.
2. **Signature verification is mandatory, real, and not stubbed** — HMAC-SHA256 over
   `'<t>.<raw_body>'` with the `whsk_…` secret, timing-safe compare, 10-min replay
   guard; **no bypass flag**, not even in dev.
3. **Idempotency everywhere** — unique `paymongo_event_id` gate + guarded transitions
   + one-pending-intent-per-customer.
4. **Amount integrity** — server-side recompute at creation; webhook re-verifies.
5. **Secrets never touch the client** — PayMongo secret key + webhook secret live
   only in Edge Function env/secrets; the app sees only the `cs_` checkout URL and the
   scoped `client_key`.
6. **No card/wallet credentials pass through us** — authorization happens inside the
   GCash app / PayMongo hosted page.
7. **RLS** — customers read only their own `payment_intents`/orders; no client writes
   to `payment_webhook_events` (service-role inserts only).
8. **Audit trail** — `payment_webhook_events` is append-only (every event, redacted
   payload, timestamps); the sweep and cancel paths also append rows.
9. **Timeout/expiry handled explicitly** — `payment.failed`, session-expired events,
   and the sweep+poll expiry all resolve to terminal states; no silent limbo.
10. **Least privilege** — service role used only inside Edge Functions, only for the
    tables/columns each function needs.
11. **Sandbox-first** — the test plan (§10.8) runs entirely on `sk_test_…` keys.
12. **No sensitive data in logs** — webhook payloads are redacted before storage.

### 10.5 Error/terminal states

| Path | orders.status | payment_status | Stock |
|---|---|---|---|
| Intent created (GCash) | `awaiting_payment` | `pending` | none held (defer-until-paid) |
| Webhook `payment.paid` | `pending` | `paid` | decremented exactly once (items materialized) |
| Webhook `payment.paid` + amount mismatch | `payment_conflict` | `paid` | decremented once, manual review |
| Webhook `payment.failed` / session expired | `cancelled` | `failed` | none held |
| Expiry sweep / poll (15 min) | `cancelled` | `failed` | none held |
| Customer cancel (RPC) | `cancelled` | `failed` | none held |

### 10.6 Edge Function + migration reference

| Asset | Role |
|---|---|
| `supabase/migrations/20260809000000_revive_paymongo_online_gcash.sql` | orders `gcash_fee_amount/_rate_bps/_vat_bps`; `payment_intents.checkout_session_id/fee_amount/fee_rate_bps`; `payment_fee_config` + `get_gcash_fee` + `set_payment_fee_config`; sweep re-ensure; deprecation comments on direct-flow objects |
| `create-gcash-payment-intent` | authN; server-side total+fee; Checkout Session creation; 15-min `expires_at`; idempotency (key + one-pending cap); returns `{order_id, checkout_url, client_key, amount, fee_amount, expires_at}` |
| `gcash-webhook` | signature verify (mandatory); idempotency gate; `payment.paid` → verify amount → materialize items → `paid`; `payment.failed`/expired → `cancelled`/`failed`; `payment_conflict` on mismatch; notifications; redacted audit rows |
| `get-payment-status` | authN + ownership check; returns order + intent state incl. fee breakdown + `cancellation_reason`; enforces expiry on read (mirrors sweep) |
| `_shared/paymongo.ts` | Checkout Sessions client + signature verification + event parsing (shared) |

### 10.7 Flutter wiring (done Aug 9, 2026)

- **`gcash_payment_service.dart`** (new) — `createIntent` (edge function, idempotency
  key), `getStatus` (poll), `cancelPending` (customer RPC), `fetchFee` (`get_gcash_fee`),
  `fetchPendingIntent`/`fetchIntentForOrder` (RLS reads), typed result models + friendly
  error mapping (409 → pending-checkout dialog).
- **`gcash_payment_screen.dart`** (new) — amount card (items+delivery, fee line, total
  due), 15-min countdown, **Open GCash → system browser** (`LaunchMode.externalApplication`),
  3s polling of `get-payment-status` (also on app-resume and deep-link return — the
  redirect is never trusted), honest terminal states (paid / failed / expired /
  cancelled / payment_conflict) with Track My Order / Back to Home. Countdown + poll
  timers are cancelled on terminal states (no leaks).
- **`checkout_screen.dart`** — GCash branch calls `createIntent` (client sends only
  product/size/quantity; idempotency key is stable per submission so retries reuse it),
  `pushReplacement`s to the payment screen. The cart is **not** cleared here — items
  stay visible while payment is awaiting (removed only on server-confirmed
  paid/conflict, in `gcash_payment_screen.dart`). Model B fee shown as its own line
  item pre-submit via `fetchFee`. 409 → resume/cancel dialog. Cash path unchanged.
- **`deep_link_service.dart` + `main.dart` `DeepLinkHost`** — `solvision://checkout/gcash/*`
  deep-link stream; warm returns skipped (the open payment screen polls), cold-start
  resumes the customer's pending checkout via `fetchPendingIntent()`.
- **`tracking_screen.dart` / `sole_status_chip.dart`** — `awaiting_payment` banner +
  countdown + resume; `payment_conflict` needs-review banner; chip styling for both.
- **`pos_screen.dart`** — untouched. Android/iOS deep-link registration for the
  `solvision://` scheme was already present from attempt #4 (only the Dart side was
  re-added).

### 10.8 Test status (honest)

- **Done:** all server code passes `deno check`; Flutter passes `flutter analyze` (no
  new issues) and all 327 unit/widget tests pass; code reviewed (payment-infra review
  + SQL review) with findings applied.
- **Pending (needs human + PayMongo test keys):** the isolated sandbox suite in
  `docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN.md` — success / failure / expiry /
  duplicate-webhook / bad-signature / amount-mismatch / RLS cross-account / stock-race
  cases against `sk_test_…`, plus a registered webhook endpoint
  (`https://<project-ref>.supabase.co/functions/v1/gcash-webhook`) with a `whsk_test_…`
  secret. **Do not switch to live keys before this passes.**
- **Deploy steps (after sandbox):** `supabase db push` (approved additive migration),
  `supabase functions deploy create-gcash-payment-intent gcash-webhook get-payment-status`
  with test env vars (`PAYMONGO_SECRET_KEY`, `PAYMONGO_PUBLIC_KEY`,
  `PAYMONGO_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).
- **⚠️ Security note:** the human shared live PayMongo keys in chat earlier; they were
  never stored or committed, and should be **rotated** in the PayMongo dashboard.
