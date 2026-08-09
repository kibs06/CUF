# Checkout & GCash Payment — Architecture

> **Last updated:** Aug 8, 2026 — **attempt #5 (gateway-free direct GCash) is fully
> implemented and wired** server-side (2 migrations) AND in the Flutter app (customer
> pay + proof screen, seller confirm/reject queue, tracking state, status chip).
> PayMongo is **not** used anywhere in the online flow — money moves peer-to-peer from
> the customer's GCash to the seller's GCash, and the seller manually confirms receipt,
> exactly like the in-store POS flow. See §6 history and §9.
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
| GCash mechanism | **Direct to seller — static QR + proof submission.** Order is created in `awaiting_payment_confirmation`; app shows the store's uploaded GCash QR/number/name + exact amount; customer pays via their own GCash app and submits a reference number + screenshot; **seller manually confirms receipt** | **Static seller QR** — customer scans seller's uploaded GCash QR; seller confirms receipt manually |
| Money movement | Customer's GCash → **seller's GCash directly**. No gateway, no platform cut, no webhook | Same — peer-to-peer |
| Order `source` | `online` | `pos` |
| Order `status` on creation | `awaiting_payment_confirmation` → `pending` after seller confirms | `received` |
| Order `payment_status` | `pending` → `paid` (seller confirms) / stays `pending` until cancelled/expired | `paid` (cash) / `pending` → `paid` (seller taps "Payment Received") |

> **The three "pending"-meanings are now cleanly separated** (brief §5.1 — documented,
> not just assumed):
>
> 1. `orders.status = 'awaiting_payment_confirmation'` — **online GCash**: order placed,
>    stock reserved, waiting for the seller to confirm the customer's proof of payment.
>    Distinct from everything below.
> 2. `orders.payment_status = 'pending'` — payment not yet confirmed. Used by **both**
>    flows: online GCash while `status='awaiting_payment_confirmation'`, and POS GCash
>    between order creation and the seller tapping "Payment Received".
> 3. `orders.status = 'pending'` — **paid and in the normal fulfillment pipeline**,
>    awaiting the seller's fulfillment actions (preparing → ready → delivered). Online
>    orders only reach this state **after** payment is confirmed.
>
> There is no longer any path where an online order sits in `status='pending'` unpaid.

Key files: `lib/screens/customer/cart_screen.dart`, `lib/screens/customer/checkout_screen.dart`,
`lib/screens/customer/gcash_pay_screen.dart`, `lib/screens/customer/tracking_screen.dart`,
`lib/screens/seller/pos_screen.dart`, `lib/screens/seller/gcash_payment_queue_screen.dart`,
`lib/screens/seller/seller_dashboard_screen.dart`, `lib/services/direct_gcash_service.dart`,
`lib/services/supabase_service.dart` (`createOrder`), `lib/providers/order_provider.dart`,
`lib/providers/cart_provider.dart`, plus the two migrations in §9.1.

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
  │  _submitCheckout():
  │    GCash        → DirectGcashService.createCheckout(...) → RPC
  │                   create_gcash_checkout → order created in
  │                   awaiting_payment_confirmation + STOCK RESERVED,
  │                   cart cleared, pushReplacement → GcashPayScreen
  │                   ⚠️ 23505 (already pending) → RESOLUTION DIALOG:
  │                     "Complete Payment" (resume existing order) or
  │                     "Cancel Pending Order" (new customer RPC —
  │                     releases stock + frees the cap → auto-retry)
  │    Cash on Pickup → orderProvider.placeOrder(...) → createOrder()
  ▼
  ┌─ GcashPayScreen (GCash only) ───────────────────────────────────┐
  │ Store's GCash QR + gcash_number + gcash_account_name            │
  │ Exact amount to send · 30-min countdown deadline                │
  │ Form: GCash reference number (required, 12–13 digits) +         │
  │       screenshot of the payment confirmation (required,         │
  │       image_picker → private payment-proofs bucket)             │
  │ "Submit Proof" → RPC submit_gcash_proof → deadline extends to   │
  │   +2h → seller notified (in-app badge)                          │
  │ Submitted state: "Waiting for the seller to confirm receipt"    │
  │   + "Track Order" → OrderTrackingScreen                         │
  └─────────────────────────────────────────────────────────────────┘
  ▼
OrderTrackingScreen — status 'awaiting_payment_confirmation' shows its
  own distinct banner + deadline countdown + "Pay via GCash again"
  resume button (if no proof yet) + opportunistic expiry sweep call
```

### Cash on Pickup path (unchanged)

`createOrder(orderData)` in `supabase_service.dart` remains the single order-creation
entry point for **cash-on-pickup only**. `payment_method` is normalized
(`'GCash' → 'gcash'`, `'card'`, else `'cash'`). It inserts the `orders` row +
`order_items` (non-atomic; orphaned order is deleted + stock errors surfaced on
item-insert failure).

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

## 4. Online GCash today (fully wired, gateway-free)

- **Server-side** (§9): migrations `20260808200000_add_direct_gcash_online_checkout.sql`
  (schema) + `20260808210000_add_direct_gcash_rpcs.sql` (five SECURITY DEFINER RPCs +
  pg_cron expiry). **No Edge Functions, no PayMongo, no webhooks.**
- **Flutter**: `checkout_screen.dart` GCash path calls `create_gcash_checkout` and hands
  off to `gcash_pay_screen.dart` (QR + amount + deadline + proof form). The seller sees
  a "Payments to confirm" card on their dashboard → `gcash_payment_queue_screen.dart`
  (Confirm / Reject with reason). The customer's `tracking_screen.dart` renders the new
  status with a live countdown and a resume button. `sole_status_chip.dart` styles the
  new status.
- The legacy fake-paid path (online GCash → instant `paid` via `createOrder`) and the
  attempt-#4 PayMongo redirect/poll path are **both gone from the UI**.

---

## 5. Orders schema (checkout-relevant columns)

```sql
orders (
  id                             UUID PK       -- ⚠️ LIVE DB: UUID. schema.sql says BIGINT — schema.sql is stale
  customer_id                    UUID → profiles(id)
  store_id                       UUID → stores(id)
  status                         TEXT  -- ONLINE GCash: awaiting_payment_confirmation → pending → …
                                            --   (confirmed) / cancelled (rejected | expired)
                                            -- CASH online / confirmed: pending → preparing → ready →
                                            --   delivered → received; + placed, cancelled,
                                            --   cancellation_requested, payment_conflict (dormant)
  total_amount                   NUMERIC
  payment_method                 TEXT  -- 'gcash' | 'cash' | 'card' (normalized)
  payment_status                 TEXT  -- CHECK IN ('paid','unpaid','pending','failed')
  fulfillment                    TEXT  -- always 'pickup' in practice
  notes                          TEXT  -- delivery address text (online)
  shipping_address               JSONB -- address snapshot (online)
  source                         TEXT  -- 'online' | 'pos'
  amount_tendered / change_amount NUMERIC -- POS cash
  payment_confirmation_deadline  TIMESTAMPTZ -- NEW: online GCash; now()+30min at creation,
                                            --   +2h from submission when proof is submitted
  gcash_reference_number         TEXT  -- POS manual flow only (seller-typed ref #)
  gcash_transaction_id           TEXT  -- dormant (attempt-#4 PayMongo usage; never written now)
  payment_verified_at            TIMESTAMPTZ -- dormant (attempt-#4 usage)
  created_at                     TIMESTAMPTZ
)
-- order_items(order_id, product_id, size, quantity, unit_price) — stock is decremented
--   by trigger `decrement_inventory_on_order` on insert; raises 'Insufficient stock' (P0001)
--   For online GCash, order_items are inserted at creation inside the RPC (stock
--   reserved); released exactly-once on reject/expire.
```

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
| 4 | PayMongo **Payment Intents** + `gcash` e-wallet redirect + verified webhook (online) | Aug 8 | ❌ **Built then replaced before production** — hit "payment provider unavailable" in practice; abandoned in favor of #5 (no gateway fees, no webhook infra, trust model matches the proven POS flow) |
| **5 (current)** | **Gateway-free direct GCash (online): static seller QR + proof submission + seller confirmation, mirroring POS** | **Aug 8** | ✅ **Fully implemented** — 2 migrations (schema + RPCs) + complete Flutter flow |

Attempts #2/#4's dormant assets: `payment_intents` / `payment_webhook_events` tables and
the `create-gcash-payment-intent` / `gcash-webhook` / `get-payment-status` Edge Functions
remain in the repo **unused and unwired** (the PayMongo `awaiting_payment` /
`payment_conflict` statuses stay legal in the orders CHECK — superset — but are dead
code paths). `docs/to be continue/GCASH_PAYMONGO_ARCHITECTURE.md` documents attempt #2
(reference only).

---

## 7. Known quirks & honest gaps

- **Screenshot upload is required** (decision, confirmed with the human) alongside the
  reference number. On a failed submit (e.g. ref already used), the just-uploaded image
  is deleted best-effort so the private bucket doesn't accumulate orphans.
- **Reference-number uniqueness is platform-wide** (per the brief's options) — a given
  12–13-digit GCash ref can prove at most one order.
- **Deadline**: 30 minutes from creation; submitting proof **extends** it to +2h (a paid
  order can never expire out from under the customer — deliberate decision, §6.3 of the
  brief).
- **One open `awaiting_payment_confirmation` order per customer** — enforced by a DB
  partial unique index (atomic; a second checkout fails `23505`). The checkout UI maps
  this to an actionable dialog: **Complete Payment** (resume the existing order's pay
  screen) or **Cancel Pending Order** (new customer RPC → releases stock + frees the
  cap → auto-retry the checkout). No more dead-end banner.
- **Stock is reserved at creation** and released **exactly once** on reject/expire
  (guarded `DELETE … RETURNING` + re-increment, serialized with `SELECT … FOR UPDATE`;
  confirm touches no `order_items`).
- **Expiry sweep** runs via a guarded pg_cron job **and** is opportunistically invoked
  from the app (dashboard card refresh + tracking screen) — idempotent, safe to run
  repeatedly.
- **Seller's FCM push on proof submission isn't fired by the RPC** (Postgres can't call
  the push edge function). The in-app realtime `seller_notifications` badge works;
  wiring the FCM push is a Flutter-side enhancement (poll or trigger → edge function).
- **Bonus fix landed here:** `notifications.order_id` was re-typed BIGINT → UUID —
  order-status notifications were silently failing to insert all along (a UUID can't
  fit a bigint). The `order_status_history.order_id` column got the same conditional fix
  so status transitions can't be aborted by that trigger.
- Online orders carry a delivery address + fixed ₱100 fee but `fulfillment` is stored as `'pickup'`.
- Online cash-on-pickup orders stay `payment_status='unpaid'` until the seller marks them paid.
- Cash-on-pickup order placement is not wrapped in a DB transaction (two-step insert with
  manual rollback of the orphaned order row) — the GCash path is atomic by design (RPC).

---

## 8. File map

| File | Role |
|---|---|
| `lib/screens/customer/cart_screen.dart` | Cart, selection, sticky Check Out bar |
| `lib/screens/customer/checkout_screen.dart` | Checkout details; GCash branch → `create_gcash_checkout` RPC → GcashPayScreen |
| `lib/screens/customer/gcash_pay_screen.dart` | **NEW** — QR + amount + deadline countdown + proof form (ref + screenshot) |
| `lib/screens/customer/tracking_screen.dart` | **UPDATED** — `awaiting_payment_confirmation` state: banner, countdown, resume button, expiry sweep |
| `lib/screens/seller/pos_screen.dart` | POS `_CheckoutSheet` — Cash + static-QR GCash (untouched) |
| `lib/screens/seller/gcash_payment_queue_screen.dart` | **NEW** — seller Confirm / Reject queue with proof + signed-URL screenshot |
| `lib/screens/seller/seller_dashboard_screen.dart` | **UPDATED** — "Payments to confirm" card (live count + queue entry + sweep) |
| `lib/screens/seller/gcash_payment_settings_screen.dart` | Seller uploads GCash QR + number/name |
| `lib/widgets/sole_status_chip.dart` | **UPDATED** — styles the new status |
| `lib/services/direct_gcash_service.dart` | **NEW** — RPC wrappers + screenshot upload/signed URLs + error mapping |
| `lib/services/supabase_service.dart` | `createOrder()` (cash-on-pickup only), payment normalizer |
| `lib/providers/cart_provider.dart` | Hybrid cart, selected items, totals |
| `lib/providers/order_provider.dart` | `placeOrder()` → createOrder; stock errors |
| `supabase/migrations/20260808200000_add_direct_gcash_online_checkout.sql` | **NEW** — status + deadline column, one-open-order index, proofs + events tables, private bucket, tightened orders UPDATE policy |
| `supabase/migrations/20260808210000_add_direct_gcash_rpcs.sql` | **NEW** — 5 SECURITY DEFINER RPCs + guarded pg_cron expiry + notifications type fixes |
| `supabase/functions/create-gcash-payment-intent` / `gcash-webhook` / `get-payment-status` | **DORMANT** — attempt #4, not wired, kept for reference |
| `docs/AI/ONLINE_GCASH_TEST_PLAN.md` | Test cases for the direct flow |

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
