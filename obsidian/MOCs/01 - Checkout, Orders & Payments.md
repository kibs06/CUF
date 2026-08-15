# 💳 Checkout, Orders & Payments

> Cart → checkout → order creation → payment (GCash/PayMongo) and order status flow. **#moc**

---

## 📌 Overview

Two distinct checkout paths, each with its own GCash story:

| | **Online (customer)** | **POS (seller, in-store)** |
|---|---|---|
| Entry | Cart → **Check Out** → `CheckoutScreen` | Seller POS → Checkout sheet |
| Payment options | **GCash** or **Cash on Pickup** | **GCash** or **Cash** |
| GCash mechanism | **PayMongo Checkout Sessions (hosted page) + HMAC-verified webhook** — order created `awaiting_payment`, **no stock held** (defer-until-paid); webhook finalizes | Static seller QR — customer scans seller's uploaded GCash QR; seller confirms manually |
| Order `source` | `online` | `pos` |
| Status on creation | `awaiting_payment` → `pending` after webhook confirms | `received` |
| `payment_status` | `pending` → `paid` (**only the signature-verified webhook** may set it) / `failed` | `paid` (cash) / `pending` → `paid` (seller taps "Payment Received") |

> **The three "pending"s are cleanly separated:**
> 1. `orders.status = 'awaiting_payment'` — online GCash: created, unpaid, **no stock held**.
> 2. `orders.payment_status = 'pending'` — payment not yet confirmed (online GCash + POS GCash).
> 3. `orders.status = 'pending'` — **paid** and in the fulfillment pipeline (only reached after webhook confirmation online).
>
> There is no path where an online order sits in `status='pending'` unpaid.

---

## 🗺️ Online checkout flow (current)

```
CartScreen (sticky bar) → CheckoutScreen (2 internal steps)
  Step 0 "Checkout Details":
    • Validation banners (out of stock / insufficient / price changed) — warn, never auto-remove; block submit
    • Order Summary · Deliver To (address book, default selected, REQUIRED)
    • Payment Method: "GCash" / "Cash on Pickup"
    • Price breakdown: Subtotal + ₱100 Delivery + GCash Fee (Model B, server-computed, own line item) + Total
  _submitCheckout():
    GCash → GcashPaymentService.createIntent → Edge Function create-gcash-payment-intent
            → order in awaiting_payment (NO stock held) + PayMongo hosted Checkout Session
            → pushReplacement → GcashPaymentScreen
            ⚠️ 409 (one-pending cap) → dialog: "Complete Payment" (resume) | "Cancel Pending" (customer RPC → auto-retry)
    Cash on Pickup → orderProvider.placeOrder() → createOrder() (unchanged)

GcashPaymentScreen (GCash only):
    Amount-to-pay card (items+delivery + fee line + Total Due) · 15-min countdown
    "Open GCash" → PayMongo hosted URL in the SYSTEM browser (never in-app webview — gcash:// handoff)
    Polls get-payment-status every 3s — deep-link return only triggers a poll, NEVER marks paid
    Terminal states: paid (verified) / failed / expired / cancelled / payment_conflict

OrderTrackingScreen — awaiting_payment shows its own banner + countdown + "Complete Payment" resume
```

### Webhook finalization (server-side, trusted)
`gcash-webhook` verifies the **PayMongo-Signature** (HMAC-SHA256 over `'<t>.<raw_body>'`, timing-safe, 10-min replay guard, **no bypass flag**) → idempotency gate on unique `paymongo_event_id` → on `payment.paid`: re-verify amount vs stored intent (mismatch → `payment_conflict`, manual review) → **materialize `order_items` from `items_snapshot`** (stock decremented HERE, exactly once) → `status='pending'`, `payment_status='paid'`, record `gcash_transaction_id` + `payment_verified_at` → notifications.

### POS GCash (unchanged, out of scope)
Seller taps GCash → `_createPendingOrder()` (`status='received'`, `payment_status='pending'`, `source='pos'`) → shows store's uploaded static QR + number/name → seller watches customer pay → "Payment Received" → `payment_status='paid'` (+ optional `gcash_reference_number`). No gateway; manual confirmation.

---

## 🧩 Components

| File | Role |
|------|------|
| `lib/screens/customer/cart_screen.dart` | Cart, per-store grouping, selection, sticky Check Out bar |
| `lib/screens/customer/checkout_screen.dart` | Details step; GCash branch → create-intent; Model B fee line; 409 dialog |
| `lib/screens/customer/gcash_payment_screen.dart` | **NEW (#6)** — amount+fee card, Open GCash (system browser), 15-min countdown, 3s poll, honest terminal states |
| `lib/screens/customer/gcash_pay_screen.dart` | **DORMANT (#5)** — QR + proof form, kept for legacy orders |
| `lib/screens/customer/tracking_screen.dart` | `awaiting_payment` + `payment_conflict` banners, resume + countdown |
| `lib/screens/seller/pos_screen.dart` | POS `_CheckoutSheet` — Cash + static-QR GCash (untouched) |
| `lib/screens/seller/gcash_payment_queue_screen.dart` | **DORMANT (#5)** — seller Confirm/Reject queue |
| `lib/screens/seller/gcash_payment_settings_screen.dart` | Seller uploads GCash QR + number/name (POS uses this) |
| `lib/services/gcash_payment_service.dart` | **NEW (#6)** — intent create / status poll / cancel / fee fetch |
| `lib/services/deep_link_service.dart` | **NEW (#6)** — `solvision://checkout/gcash/*` stream + matcher |
| `lib/services/direct_gcash_service.dart` | **DORMANT (#5)** — RPC wrappers for the legacy direct flow |
| `lib/services/supabase_service.dart` | `createOrder()` — cash-on-pickup only now |
| `lib/providers/cart_provider.dart` / `order_provider.dart` | Totals, selection; `placeOrder()` |
| `supabase/functions/create-gcash-payment-intent` | Server-side total+fee recompute, idempotent, 15-min expiry |
| `supabase/functions/gcash-webhook` | HMAC-verified, idempotent, fee-aware, finalizes orders |
| `supabase/functions/get-payment-status` | Authenticated poll + expiry enforcement |
| `supabase/functions/_shared/paymongo.ts` | Checkout Sessions helper + signature verify + event parsing |
| `supabase/migrations/20260809000000_revive_paymongo_online_gcash.sql` | Fee config + RPCs + orders/`payment_intents` columns + sweep re-ensure |

---

## 🗄️ Data model

- `orders` — `status` (awaiting_payment → pending/preparing/ready/delivered/received; cancelled; payment_conflict), `payment_method` ('gcash'|'cash'|'card'), `payment_status` (CHECK in paid/unpaid/pending/failed), `total_amount` (products+delivery, **fee NOT included** — seller revenue basis), `source` ('online'|'pos'), `shipping_address` JSONB, `gcash_fee_amount/_rate_bps/_vat_bps` (Model B snapshot), `gcash_transaction_id`, `payment_verified_at`, `payment_confirmation_deadline` (legacy #5).
- `order_items` — stock decremented by trigger `decrement_inventory_on_order` (raises 'Insufficient stock' P0001). **Online GCash: inserted only by the webhook** (defer-until-paid).
- `payment_intents` — one per online GCash checkout: `checkout_session_id` (unique), `client_key`, `amount` (total+fee), `fee_amount`, `items_snapshot`, `status`, `expires_at` (15 min); **partial unique `customer_id WHERE status='pending'`** = one-pending cap.
- `payment_webhook_events` — append-only audit + idempotency gate (`paymongo_event_id` UNIQUE).
- `payment_fee_config` — singleton (id=1): `rate_bps` seeded 223 (2.23%), `vat_bps` 1200 (12%), editable only via `set_payment_fee_config` admin RPC.
- Legacy (#5): `gcash_payment_proofs` (ref 12–13 digits, platform-unique), `order_payment_events` (append-only), `payment-proofs` private bucket.

## 💰 Fee model (Model B — surcharge to customer)

`charged = ceil_to_cent(total / (1 − r_total))`, `r_total = (rate_bps/10000) * (1 + vat_bps/10000)`. Fee is **disclosed as its own line item**, recomputed server-side at intent creation, re-verified by the webhook, snapshotted per order so seller revenue on `total_amount` stays honest.

## 🔐 Security posture

1. **Server is the only source of truth for `payment_status`** — no client write path; only the webhook (service role) sets `paid`.
2. **Signature verification mandatory, not stubbed** — HMAC-SHA256, timing-safe, 10-min replay guard, no bypass flag.
3. **Idempotency everywhere** — unique `paymongo_event_id` gate + guarded `UPDATE … WHERE status='awaiting_payment'` + one-pending-intent-per-customer.
4. **Amount integrity** — server recompute at creation; webhook re-verifies; mismatch → `payment_conflict`.
5. **Secrets never touch the client** — PayMongo keys live only in Edge Function env; app sees only the `cs_` URL + scoped `client_key`.
6. **Orders UPDATE policy tightened** — store-scoped (`stores.owner_id = auth.uid()`) or admin; a seller can no longer flip payment_status cross-store.

## ⚠️ Gotchas

- **Sandbox verification pending**: attempt #6 never exercised against PayMongo test keys. **Do not switch to live keys** before `docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN.md` passes.
- Live PayMongo keys were shared in chat once — never committed; **rotate them** in the PayMongo dashboard.
- `docs/AI/checkout_screen_and_app_constants.md` is a **stale source dump** — `CHECKOUT_AND_GCASH_ARCHITECTURE.md` is the source of truth.
- Cart keeps items while payment is awaiting (user-requested); they're removed (quantity-aware) only on server-confirmed paid/conflict.
- Cash-on-pickup placement isn't wrapped in a DB transaction (two-step insert + manual orphan rollback) — known, unchanged.
- Stock decrements **exactly once, only after verified payment** — the anti-pattern that killed attempt #2.
- Revenue combines online + POS; online revenue filters `status != 'cancelled'` AND `payment_status = 'paid'`.

## 📚 Deep-dive docs

- [[docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE|Checkout & GCash architecture]] — **the source of truth** (attempts history §6, attempt #6 §10)
- [[docs/createOrder_function_reference|createOrder() reference]] — annotated + flow diagram
- [[docs/checkout_submit_analysis|Checkout submit analysis]]
- [[docs/addToCart_and_fetchCart_reference|Add-to-cart + fetchCart reference]]
- [[docs/FIX_false_error_and_cart_clear_v6|False error & cart clear fix v6]]
- [[docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN|PayMongo online GCash test plan]] (attempt #6)
- [[docs/AI/ONLINE_GCASH_TEST_PLAN|Online GCash test plan]] (legacy direct flow)
- [[docs/to be continue/GCASH_PAYMONGO_ARCHITECTURE|GCash/PayMongo architecture]] — attempt #2 reference only
- [[docs/debug/CUSTOMER_ORDER_PROCESS|Customer order process (debug)]]
- [[docs/debug/REVIEW_INSERT_PAYLOAD_AND_ORDER_STATUSES|Review insert payload & order statuses (debug)]]
- [[docs/debug/SELLER_ORDER_CONFIRMATION_ARCHITECTURE|Seller order confirmation (debug)]]
- [[docs/seller-order-flow-architecture|Seller order flow architecture]]
- [[docs/AI/SELLER_ORDER_FLOW_ARCHITECTURE|Seller order flow (AI)]]

## 🔗 Related

- [[obsidian/MOCs/02 - Customer App|📱 Customer App]] — cart & checkout screens
- [[obsidian/MOCs/03 - Seller Module|👞 Seller Module]] — seller order processing, POS
- [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database & Supabase]] — triggers, `orders` schema, RLS
