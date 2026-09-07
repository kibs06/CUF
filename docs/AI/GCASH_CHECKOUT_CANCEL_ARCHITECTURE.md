# GCash Checkout Cancellation — Architecture

> **For AI agents:** This document explains why a user sees the "Checkout cancelled" screen (see attached screenshot) when trying to place a GCash order, and what the full cancellation path looks like.

---

## The symptom

The user sees a screen titled **"GCash Payment"** with:
- A gray X-in-circle icon + **"Checkout cancelled"** header
- Subtitle: *"This checkout was cancelled. No charge was made — you can place a new order anytime."*
- A white card showing the amount breakdown:
  - **₱410.25** (total to pay)
  - Items + Delivery: ₱400.00
  - GCash Service Fee: ₱10.25
  - Total Due: ₱410.25
- A dark brown **"Back to Home"** button

This screen is rendered by `GcashPaymentScreen` when its internal state is `_PayPhase.cancelled`.

---

## How the user gets here (cancellation paths)

There are **three ways** a GCash checkout ends up cancelled:

### Path A — Customer taps "Cancel this checkout" (most likely cause)

The user is on `GcashPaymentScreen` (the screen with the "Open GCash" button) and taps the **"Cancel this checkout"** text button below it.

1. A confirmation dialog appears: *"Cancel this checkout? No charge has been made yet…"* with **Keep It** / **Yes, Cancel** buttons.
2. If the user taps **Yes, Cancel**, `_cancelCheckout()` calls `GcashPaymentService().cancelPending(orderId)`.
3. This invokes the `cancel_my_pending_payment_intent` RPC on the server, which:
   - Checks the order is still in `awaiting_payment` status (not already paid/expired)
   - Updates the order to `status='cancelled'`, `payment_status='failed'`
   - Sets `cancellation_reason='Cancelled by customer'`
   - Marks the `payment_intents` row as `cancelled`
   - Appends an audit row to `payment_webhook_events`
4. The screen's `_phase` switches to `_PayPhase.cancelled` and re-renders with the cancelled UI.

### Path B — Payment window expired (15 minutes)

The `create-gcash-payment-intent` edge function sets `expires_at = now() + 15 minutes`. Two mechanisms enforce this:

1. **pg_cron sweep** runs every 5 minutes → cancels expired intents
2. **`get-payment-status` edge function** enforces expiry on every poll (mirrors the sweep)

When either runs, the order transitions to `cancelled` with `cancellation_reason='Payment session expired'`. The app's 1-second countdown timer also forces an immediate poll when it hits zero, so the UI updates promptly.

### Path C — PayMongo webhook reports failure

If PayMongo sends a `payment.failed` or `checkout_session.expired` webhook event (HMAC-signature-verified), the `gcash-webhook` edge function:
- Idempotency-gates on `paymongo_event_id` (unique)
- Sets `orders.status='cancelled'`, `payment_status='failed'`
- Records `cancellation_reason` (e.g. "Payment not completed")
- Sends customer notification

No stock is released — none was ever held (`awaiting_payment` is defer-until-paid).

---

## State machine (online GCash — attempt #6)

```
awaiting_payment (payment_status='pending', NO stock held, expires_at=+15min)
  │
  ├── webhook payment.paid  ──► status='pending', payment_status='paid'
  │                              (order_items materialized, stock decremented once)
  │
  ├── webhook payment.failed / expired
  │   OR sweep/poll expiry
  │   OR customer cancel RPC ──► status='cancelled', payment_status='failed'
  │
  └── amount mismatch on payment.paid
       ──► status='payment_conflict', payment_status='paid' (manual review)
```

**Every `awaiting_payment` order resolves to exactly one of:** `pending` (paid), `cancelled`, or `payment_conflict`. Never stuck.

---

## Key files

| File | Role in cancellation |
|---|---|
| `lib/screens/customer/gcash_payment_screen.dart` | Renders the "Checkout cancelled" screen when `_phase == _PayPhase.cancelled`; `_cancelCheckout()` is the user-facing cancel action |
| `lib/services/gcash_payment_service.dart` | `cancelPending(orderId)` — calls `cancel_my_pending_payment_intent` RPC; returns `true` if actually cancelled, `false` if already resolved |
| `lib/services/deep_link_service.dart` | Handles `solvision://checkout/gcash/cancel` deep link return (informational only — triggers a poll, never marks anything paid) |
| `lib/screens/customer/checkout_screen.dart` | GCash branch calls `GcashPaymentService().createIntent()` → navigates to `GcashPaymentScreen`; 409 (one-pending cap) → resume/cancel dialog |
| `supabase/functions/create-gcash-payment-intent/index.ts` | Creates the order in `awaiting_payment` + PayMongo checkout session; 15-min expiry; idempotent on `idempotency_key` + one-pending-per-customer index |
| `supabase/functions/gcash-webhook/index.ts` | HMAC-verified webhook; handles `payment.failed`/`expired` → cancelled; amount mismatch → `payment_conflict` |
| `supabase/functions/get-payment-status/index.ts` | AuthN poll endpoint; enforces expiry on read; returns order + intent state including `cancellation_reason` |

---

## Important: what cancellation does NOT do

- **No money moved** — the order was created in `awaiting_payment` with no stock held and no charge made. Cancellation is safe.
- **No stock released** — there's nothing to release; stock is only decremented when the webhook materializes `order_items` on a confirmed `payment.paid`.
- **Cart items stay** — items are NOT removed from the cart when the checkout is created (user-requested behavior). They remain visible in "My Cart" so the user can retry. They are only removed after a server-confirmed `paid` or `payment_conflict`.
- **The deep-link return is never trusted** — even if the user was redirected to `solvision://checkout/gcash/cancel`, the app only triggers a poll; it never flips to "cancelled" from the link itself.

---

## Why the user might hit this when "trying to order"

Likely scenarios (in order of probability):

1. **Accidental tap** — the "Cancel this checkout" text button is below the "Open GCash" primary button on `GcashPaymentScreen`. Easy to tap by mistake.
2. **The 15-min window expired** while the user was reading/preparing — the countdown on the payment screen reaches 0, the poll catches the expiry, and the screen flips to cancelled.
3. **The user already had a pending checkout** (one-pending-per-customer cap) and the 409 dialog's "Cancel Pending" path was taken — this cancels the existing intent and the new checkout may have also been created then cancelled.
4. **Payment failed in GCash** — the customer opened the hosted checkout, started authorizing, then cancelled inside the GCash app; PayMongo sends `payment.failed` and the webhook cancels the order.

---

## Debugging tips for AI agents

- Check `orders.status` and `orders.cancellation_reason` for the order ID — `cancelled_by_customer` = Path A, `Payment session expired` = Path B, `Payment not completed` / `not completed` = Path C.
- Check `payment_intents.status` — `cancelled` vs `failed` vs `expired`.
- Check `payment_webhook_events` for the event that triggered the cancellation (look for `event_type` + `status` columns).
- The `GcashPaymentScreen.isOpen` static flag gates the deep-link handler — warm returns (user already on the payment screen) only trigger a poll; cold-start returns resume via `fetchPendingIntent()`.

---

## How to diagnose a specific cancellation (SQL)

Run this in your Supabase SQL Editor (replace `'<ORDER_ID>'` with the actual UUID):

```sql
-- 1. The order row — ground truth
SELECT
  id,
  status,
  payment_status,
  total_amount,
  cancellation_reason,
  cancellation_details,
  created_at,
  customer_id,
  store_id
FROM orders
WHERE id = '<ORDER_ID>';

-- 2. The payment intent — shows expiry + what was charged
SELECT
  id,
  order_id,
  status,            -- pending | succeeded | failed | expired | cancelled
  amount,            -- what customer was charged (total + fee)
  fee_amount,        -- Model B surcharge
  expires_at,
  checkout_session_id,
  checkout_url,
  customer_id,
  created_at
FROM payment_intents
WHERE order_id = '<ORDER_ID>';

-- 3. Webhook events — the event that triggered the state change (if any)
SELECT
  paymongo_event_id,
  event_type,        -- payment.paid | payment.failed | checkout_session.payment.paid | checkout_session.expired | etc.
  status,            -- processing | failed | ignored_stale | amount_mismatch | rejected_signature | ...
  livemode,
  received_at,
  processed_at,
  redacted_payload
FROM payment_webhook_events
WHERE order_id = '<ORDER_ID>'
ORDER BY received_at DESC;

-- 4. Who the customer is (for cross-check)
SELECT id, role, email
FROM profiles
WHERE id = '<CUSTOMER_ID_FROM_ORDERS>';
```

---

## Decision table — what you see → root cause

Look at `orders.cancellation_reason` first. That's the fastest signal:

| `cancellation_reason` | `payment_intents.status` | `payment_webhook_events` | Root cause |
|---|---|---|---|
| **`Cancelled by customer`** | `cancelled` | likely empty, or a synthetic `checkout_session.duplicate_cancelled` / `checkout_session.create_failed` row | **Path A** — user tapped "Cancel this checkout" on `GcashPaymentScreen`. `_cancelCheckout()` → `cancel_my_pending_payment_intent` RPC. |
| **`Payment session expired`** | `expired` | likely empty (sweep or poll did it, no webhook) | **Path B** — the 15-min window closed. pg_cron sweep or `get-payment-status` poll enforced it. |
| **`Payment not completed`** / `not completed` / `failed` | `failed` or `expired` | a `payment.failed` or `checkout_session.expired` event | **Path C** — PayMongo sent a failure webhook; the customer started in GCash but aborted inside the GCash app. |
| **`Amount mismatch`** | `succeeded` | event with status `amount_mismatch` | Not a normal cancellation — money *was* captured but amount didn't match. Goes to `payment_conflict`, not `cancelled`. Unlikely here. |
| **`Duplicate checkout detected`** | `failed` | synthetic `checkout_session.duplicate_cancelled` row | Concurrent intent creation raced — the loser's order was cancelled. Could happen on double-tap at checkout. |
| **`Payment gateway error`** | `failed` | synthetic `checkout_session.create_failed` row | `create-gcash-payment-intent` couldn't reach PayMongo. Order created then immediately cancelled. Rare — usually a snackbar error, not a cancelled screen. |
| **NULL** (no `cancellation_reason`) but `status='cancelled'` and `payment_status='failed'` | `expired` or `failed` | check events | Something resolved it without setting a reason — possibly a migrated/legacy order, or a gap. Worth flagging. |

---

## Most likely cause for "when I try to order"

**If the user saw the "Open GCash" screen first, then later saw "Checkout cancelled":**

1. **Accidental tap** — the "Cancel this checkout" text button is below the "Open GCash" primary button. If the user was reading the amount card and tapped lower on the screen, they may have hit it. A confirmation dialog ("Cancel this checkout? No charge has been made yet…") should have appeared first — if they don't remember that dialog, this is less likely.

2. **15-minute expiry** — if the user opened GCash in the system browser, authorized the payment, but the GCash app handoff took too long, or they got distracted, the window could have closed. The countdown on the payment screen shows this live. When it hits 00s, the next poll enforces expiry immediately (not just waiting for the 5-min sweep).

3. **GCash app cancelled the payment** — the user opened the hosted checkout, the GCash app popped up, but they cancelled *inside* GCash (back button, close). PayMongo sends `payment.failed` and the webhook cancels the order.

**If the user went straight from Checkout Details → "Checkout cancelled" without ever seeing the "Open GCash" screen:**

That points to **Path A via the 409 dialog** — the user had an existing pending checkout (one-pending-per-customer cap), the checkout hit 409, showed the "You have an unfinished GCash checkout" dialog with **Complete Payment** / **Cancel Pending** options, and "Cancel Pending" was chosen. That cancels the existing intent, then the new checkout attempt may have also been created and immediately cancelled (or the user navigated away and the existing one expired).

Or **Path B** — the user had a pending checkout from earlier that sat unattended past 15 minutes, then came back and tried to order again.

---

## What to tell the user (support scenario)

- If `cancellation_reason = 'Cancelled by customer'`: "It looks like the checkout was cancelled from the payment screen. This is harmless — no charge was made. You can place a new order anytime."
- If `cancellation_reason = 'Payment session expired'`: "The payment window (15 minutes) closed before the payment was completed. You can place a new order anytime."
- If there's a `payment.failed` webhook event: "The payment wasn't completed in GCash. No charge was made. Please try again."

**If this is happening repeatedly**, the most actionable fix is reducing accidental cancellations on `GcashPaymentScreen` (the cancel button is a thin text button below a large primary button — easy to tap by mistake). That's a UI change, not a backend one.
