# Checkout & GCash Payment — Architecture

> **Last updated:** Aug 8, 2026 — **attempt #4 (real online GCash) is fully wired**
> server-side AND in the Flutter checkout. The migration + three Edge Functions are in
> the repo, and `checkout_screen.dart` now drives the redirect + polling flow. See §9.
>
> **Purpose:** End-to-end picture of how an order is placed and how GCash fits in,
> accurate to the **current** code. Read this first if you are touching checkout,
> orders, cart, payment, or the POS.
>
> ⚠️ `docs/AI/checkout_screen_and_app_constants.md` is a **stale source dump** from an
> older iteration (it shows a PayMongo webhook-wait flow that no longer exists). Treat
> this document as the source of truth.

---

## 1. The big picture

SoleVision has **two distinct checkout paths**, each with its own GCash story:

| | **Online (customer)** | **POS (seller, in-store)** |
|---|---|---|
| Entry point | Cart screen → **Check Out** → `CheckoutScreen` | Seller POS → **Checkout sheet** |
| Payment options | **GCash** or **Cash on Pickup** | **GCash** or **Cash** |
| GCash mechanism | **Redirect into GCash via PayMongo Payment Intents (system browser); verified webhook finalizes; app polls `get-payment-status` and confirms only when paid** | **Static seller QR** — customer scans seller's uploaded GCash QR; seller confirms receipt manually |
| Order `source` | `online` | `pos` |
| Order `status` on creation | `awaiting_payment` (new) → `pending` after paid webhook | `received` |
| Order `payment_status` | `pending` → `paid` (webhook only) / `failed` | `paid` (cash) / `pending` → `paid` (seller taps "Payment Received") |

> **The two "pending" meanings are now cleanly separated:**
> `orders.status='awaiting_payment'` = online GCash, waiting for webhook confirmation;
> `orders.payment_status='pending'` = payment created but not confirmed (used by both
> flows). The old collision — online orders sitting in `status='pending'` while unpaid —
> is gone for GCash: online orders only reach `status='pending'` **after** payment.

Key files: `lib/screens/customer/cart_screen.dart`, `lib/screens/customer/checkout_screen.dart`,
`lib/screens/seller/pos_screen.dart`, `lib/services/supabase_service.dart` (`createOrder`),
`lib/providers/order_provider.dart`, `lib/providers/cart_provider.dart`,
`supabase/functions/create-gcash-payment-intent/`, `supabase/functions/gcash-webhook/`,
`supabase/functions/get-payment-status/`.

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
  │ • Price breakdown — Subtotal, ₱100 Delivery Fee, Estimated      │
  │   delivery date (utils/delivery_date.dart), Total               │
  │ • "Complete Order" (SolePrimaryButton)                          │
  └─────────────────────────────────────────────────────────────────┘
  │  _submitCheckout():  validate → re-validate stock →
  │    orderProvider.placeOrder(...) → createOrder() in DB
  │    (GCash currently still flows through this fake-paid path —
  │    §9 shows the wiring that replaces it)
  ▼
  ┌─ Step 1 "Order Confirmed" ───────────────────────────────────────┐
  │ Animated checkmark · Order # · Total · Payment Type             │
  │ "Track My Order" → OrderTrackingScreen   · "Back to Home"       │
  └─────────────────────────────────────────────────────────────────┘
```

### placeOrder → createOrder (`lib/providers/order_provider.dart` → `supabase_service.dart`)

`createOrder(orderData)` is the single order-creation entry point for the **cash** path
and the **legacy** path. `payment_method` is normalized (`'GCash' → 'gcash'`, `'card'`,
else `'cash'`). It inserts the `orders` row + `order_items` (non-atomic; orphaned order
is deleted + stock errors surfaced on item-insert failure). **Once the Flutter GCash
path is wired to `create-gcash-payment-intent`, `createOrder` is used for cash-on-pickup
only** (online GCash bypasses it).

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
manual by the seller. **This flow is untouched by attempt #3.**

---

## 4. Online GCash today (fully wired)

- **Server-side** (§9): migration `20260808120000_add_online_gcash_payments.sql` +
  3 Edge Functions.
- **Flutter**: `checkout_screen.dart` GCash path calls `create-gcash-payment-intent`
  (via `lib/services/gcash_payment_service.dart`), opens the redirect in the system
  browser, listens for the `solvision://checkout/gcash` deep link (or the
  "I've Completed Payment" button), polls `get-payment-status`, and only shows
  "Order Confirmed" once the order is actually `paid`. Cash on Pickup still uses
  `createOrder()` unchanged.
- The legacy fake-paid path (online GCash → instant `paid` via `createOrder`) is
  **no longer reachable** from the UI.

---

## 5. Orders schema (checkout-relevant columns)

```sql
orders (
  id                       UUID PK          -- ⚠️ LIVE DB: UUID. schema.sql says BIGINT — schema.sql is stale
  customer_id              UUID → profiles(id)
  store_id                 UUID → stores(id)
  status                   TEXT  -- ONLINE GCash: awaiting_payment→pending→…
                                 -- POS: received directly; cash online: pending→…
                                 -- + placed, preparing, ready, delivered, received,
                                 --   cancelled, cancellation_requested,
                                 --   payment_conflict (money captured, unfulfillable)
  total_amount             NUMERIC
  payment_method           TEXT  -- 'gcash' | 'cash' | 'card' (normalized)
  payment_status           TEXT  -- CHECK IN ('paid','unpaid','pending','failed')
  fulfillment              TEXT  -- always 'pickup' in practice
  notes                    TEXT  -- delivery address text (online)
  shipping_address         JSONB -- address snapshot (online)
  source                   TEXT  -- 'online' | 'pos'
  amount_tendered / change_amount NUMERIC  -- POS cash
  items_snapshot           JSONB -- NEW: line items captured at intent creation;
                                 -- materialized into order_items on payment.paid
  gcash_reference_number   TEXT  -- POS manual flow only (seller-typed ref #)
  gcash_transaction_id     TEXT  -- NEW usage: online webhook writes PayMongo pay_xxx
  payment_verified_at      TIMESTAMPTZ -- NEW usage: online webhook confirmation time
  created_at               TIMESTAMPTZ
)
-- order_items(order_id, product_id, size, quantity, unit_price) — stock is decremented
--   by trigger `decrement_inventory_on_order` on insert; raises 'Insufficient stock' (P0001)
```

New tables (`20260808120000_add_online_gcash_payments.sql`):

| Table | Purpose | RLS |
|---|---|---|
| `payment_intents` | one row per PayMongo intent (order_id, idempotency_key UNIQUE per customer, pi_id, client_key, checkout_url, amount, status pending/succeeded/failed/expired/cancelled, expires_at) | SELECT own only; **no write policies** |
| `payment_webhook_events` | append-only webhook log; `paymongo_event_id UNIQUE` = idempotency key; redacted payload | no policies (service role only) |

---

## 6. GCash history — why the current design is what it is

| # | Approach | Date | Outcome |
|---|---|---|---|
| 1 | PayMongo **Sources** API + QR image | ~Jul 29 | ❌ GCash scanner rejected non-QR-Ph code |
| 2 | PayMongo **QR Ph** Payment Intents + webhook | Jul 30 | ❌ Abandoned — webhook signature verification was a **stub**, inventory timing bugs |
| 3 | Manual static QR (POS only) | Aug 6 | ✅ Live for POS |
| **4 (current)** | **Online: PayMongo Payment Intents, `gcash` e-wallet redirect + verified webhook** | **Aug 8** | ✅ **Server-side done** (migration + 3 functions). Flutter wiring pending |

Attempt #2's dormant assets: `gcash_transaction_id` / `payment_verified_at` columns are
**now reused** by the attempt-#4 webhook; the old `create-gcash-payment` function and
`_shared/paymongo.ts` QR-Ph helpers are kept for back-compat (POS does not use them).
`docs/to be continue/GCASH_PAYMONGO_ARCHITECTURE.md` documents attempt #2 (reference only).

---

## 7. Known quirks & honest gaps

- **Flutter GCash wiring pending** — the app still uses the fake-paid path until §9's
  UI work lands.
- Online orders carry a delivery address + fixed ₱100 fee but `fulfillment` is stored as `'pickup'`.
- Online cash-on-pickup orders stay `payment_status='unpaid'` until the seller marks them paid.
- Order placement is not wrapped in a DB transaction (two-step insert with manual rollback
  of the orphaned order row) — the GCash path avoids this by design (order_items are only
  inserted by the webhook after payment).
- PayMongo edge-function env vars must be set via `supabase secrets set` before deploy (§9.5).

---

## 8. File map

| File | Role |
|---|---|
| `lib/screens/customer/cart_screen.dart` | Cart, selection, sticky Check Out bar |
| `lib/screens/customer/checkout_screen.dart` | 2-step checkout UI (details → confirmation) |
| `lib/screens/seller/pos_screen.dart` | POS `_CheckoutSheet` — Cash + static-QR GCash |
| `lib/screens/seller/gcash_payment_settings_screen.dart` | Seller uploads GCash QR + number/name |
| `lib/providers/cart_provider.dart` | Hybrid cart, selected items, totals |
| `lib/providers/order_provider.dart` | `placeOrder()` → createOrder; stock errors |
| `lib/services/supabase_service.dart` | `createOrder()`, payment normalizer |
| `supabase/migrations/20260808120000_add_online_gcash_payments.sql` | **NEW** — statuses, tables, RLS, expiry sweep |
| `supabase/functions/create-gcash-payment-intent/index.ts` | **NEW** — auth, stock+total recompute, order+intent |
| `supabase/functions/gcash-webhook/index.ts` | **NEW** — signature-verified, idempotent finalize |
| `supabase/functions/get-payment-status/index.ts` | **NEW** — authenticated status check |
| `supabase/functions/_shared/paymongo.ts` | PayMongo helpers + real signature verification |
| `supabase/config.toml` | `[functions.gcash-webhook] verify_jwt = false` |
| `docs/AI/ONLINE_GCASH_TEST_PLAN.md` | **NEW** — test cases incl. every §7 edge case |

---

## 9. NEW — Real online GCash flow (server-side, attempt #4)

### 9.1 Flow

```
CheckoutScreen (GCash selected)
  │  [Flutter wiring pending — see §9.6]
  ▼
1. POST /functions/v1/create-gcash-payment-intent   (JWT required)
   body: { idempotency_key, items:[{product_id,size,quantity}],
           delivery_address, shipping_address }
   Server:  revalidates stock, recomputes total from CURRENT product prices
            + ₱100 delivery (NEVER trusts the client total) →
            creates orders row (status='awaiting_payment', payment_status='pending',
            items_snapshot, NO order_items → stock untouched) →
            creates PayMongo Payment Intent (gcash e-wallet, amount in centavos) →
            returns { order_id, payment_intent_id, checkout_url, client_key, expires_at }
  ▼
2. App opens checkout_url in the SYSTEM BROWSER → customer authorizes in GCash app
   (return_url = PUBLIC_RETURN_URL deep link; informational only)
  ▼
3. PayMongo → POST /functions/v1/gcash-webhook  (public, signature-verified)
   payment.paid   → verify signature → idempotency gate → amount check →
                     materialize order_items from items_snapshot (stock decrements
                     via existing trigger) → orders: status='pending',
                     payment_status='paid', gcash_transaction_id=pay_xxx,
                     payment_verified_at=now()
   payment.failed → order cancelled, payment_status='failed'
   (unknown events logged; duplicates no-op; signature failures 401 + logged)
  ▼
4. App (after returning from browser) polls get-payment-status / the order row
   and only shows "Order Confirmed" once payment_status='paid'.
```

### 9.2 Security posture (brief §2, all implemented)

1. **Server-only payment status writes** — the client role has **no** INSERT/UPDATE
   policy on `payment_intents`; only the webhook (service role) sets `paid`.
2. **Signature verification is real and mandatory** — `verifyWebhookSignature()`
   HMAC-SHA256s `timestamp + "." + rawBody` with `PAYMONGO_WEBHOOK_SECRET`, constant-time
   compare, ±10 min replay guard. **No bypass flag exists.**
3. **Idempotency** — `payment_webhook_events.paymongo_event_id UNIQUE` (first insert wins;
   duplicate deliveries → 200 no-op; a previously-failed attempt is re-claimed on retry and
   reprocessed safely); `payment_intents UNIQUE(customer_id, idempotency_key)` + active-
   pending-intent lookup (compared via an `items_fingerprint` so a stale pending intent for
   a *different* cart is rejected, not silently paid for) **plus a DB-level partial unique
   index** (`uq_payment_intents_one_pending_per_customer` on `customer_id WHERE status='pending'`)
   → double-taps, retries, wrong-cart payments, and concurrent requests from two devices
   cannot double-charge.
   The webhook's stock materialization is **diff-based and idempotent**: only snapshot items
   not already present in `order_items` are inserted, so a retry after a mid-materialization
   crash fills the gap rather than under-filling or double-decrementing.
4. **Amount integrity** — server recomputes the total from current product prices; the
   webhook re-checks the gateway charge vs order total; mismatches → `payment_conflict`
   (loudly logged, never silently accepted).
5. **Secrets never reach the client** — PayMongo secret + webhook secret are Edge Function
   env vars only; the client receives `client_key` (scoped to one intent) + redirect URL.
6. **Audit trail** — every webhook event, status transition (`order_status_history` via
   existing trigger) and intent is logged; webhook payloads are stored **redacted**.
7. **Expiry** — `payment_intents.expires_at` (default 30 min) + a pg_cron sweep that
   expires intents and cancels stuck `awaiting_payment` orders.

### 9.3 Stock timing decision (defer-until-paid)

Chosen deliberately with the brief's §7.2 in mind:

- **No stock is touched at intent creation.** `order_items` are inserted only by the
  webhook after `payment.paid`, which triggers the existing decrement trigger.
- Upside: abandoned checkouts never hold stock; no compensating release logic needed.
- Risk handled: two customers can pass intent creation for the last unit — the **loser's**
  webhook fails the `order_items` insert and the order goes to **`payment_conflict`**
  (payment_status='paid' — the money is captured; manual review/refund required).
  A paid order is **never** auto-deleted (§7.6).
- Alternative (reserve-at-creation) is documented in the test plan for comparison.

### 9.4 Error/terminal states

| Path | orders.status | payment_status |
|---|---|---|
| Intent created | `awaiting_payment` | `pending` |
| Webhook `payment.paid` (success) | `pending` | `paid` |
| Webhook `payment.failed` / abandonment | `cancelled` | `failed` |
| pg_cron expiry sweep | `cancelled` | `failed` |
| Stock conflict after charge / amount mismatch / late payment | `payment_conflict` | `paid` (manual review) |

### 9.5 Env vars + deploy

```bash
supabase secrets set PAYMONGO_SECRET_KEY=sk_test_... \
  PAYMONGO_WEBHOOK_SECRET=whsk_... \
  PUBLIC_RETURN_URL=solvision://checkout/gcash \
  GCASH_PAYMENT_EXPIRY_MINUTES=30 \
  PAYMONGO_LIVEMODE=false   # true ONLY when live keys are wired

supabase functions deploy create-gcash-payment-intent   # verify_jwt = true (default)
supabase functions deploy get-payment-status            # verify_jwt = true (default)
supabase functions deploy gcash-webhook --no-verify-jwt # public, signature inside
supabase db push                                        # apply the migration
```

Register the webhook URL in the PayMongo dashboard (events: `payment.paid`,
`payment.failed`) and copy the `whsk_…` secret into `PAYMONGO_WEBHOOK_SECRET`.

### 9.6 Flutter wiring (done Aug 8, 2026)

- **`lib/services/gcash_payment_service.dart`** (new) — `createIntent()` +
  `getStatus()` wrappers around the edge functions with friendly error mapping
  (surfaces the server's `{error}` body via `FunctionException`).
- **`checkout_screen.dart`** — GCash radio now calls `create-gcash-payment-intent`
  (server recomputes the total; client sends only product/size/quantity) instead of
  `createOrder()`. Cash on Pickup is unchanged.
- Opens `checkout_url` in the **system browser** (`launchUrl`, external application).
- **Deep link `solvision://checkout/gcash`** via the `app_links` package
  (Android intent-filter + iOS `CFBundleURLTypes`). The "I've Completed Payment"
  button covers every return path — the link is a convenience, not a dependency.
- Polls `get-payment-status` (2 s interval, ~60 s budget) and shows **Order Confirmed
  only once `paid`**. Failed/expired → distinct message + Try Again (fresh idempotency
  key). The cart is cleared (server + local) only on confirmed payment; abandoning the
  flow leaves the cart intact (the pending order is closed by the server expiry sweep).
- Do **not** touch `pos_screen.dart` (still untouched).
