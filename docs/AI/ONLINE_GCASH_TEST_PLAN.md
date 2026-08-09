# Online GCash — Test Plan (attempt #5, gateway-free direct)

> Companion to `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` §9. This covers the
> **direct** flow: order reserved → customer pays seller directly via GCash → submits
> proof → seller confirms/rejects → expiry fallback. There is **no gateway, no
> PayMongo, no webhook, no secrets** — setup is just `supabase db push`.
>
> Status: migration + RPCs written; **not yet applied/tested** against a dev DB.

---

## 0. Pre-requisites

```bash
supabase db push        # applies 20260808200000, 20260808210000, 20260808230000
```

Verify the objects landed:

```sql
SELECT proname FROM pg_proc WHERE proname IN
  ('create_gcash_checkout','submit_gcash_proof','confirm_gcash_payment',
   'reject_gcash_payment','expire_overdue_gcash_orders',
   'cancel_my_pending_gcash_checkout');
SELECT to_regclass('public.gcash_payment_proofs'), to_regclass('public.order_payment_events');
SELECT status FROM orders WHERE status = 'awaiting_payment_confirmation' LIMIT 0; -- no error
SELECT 1 FROM storage.buckets WHERE id = 'payment-proofs';
SELECT count(*) FROM cron.job WHERE jobname = 'expire-online-gcash-payments'; -- 1
```

---

## 1. RPC-level tests (isolated — do these before the app wiring)

### 1.1 `create_gcash_checkout`

| # | Case | Expect |
|---|---|---|
| 1.1a | Called without auth / as a seller | Denied (RLS/role check) |
| 1.1b | Happy path, valid items + address | Order `status='awaiting_payment_confirmation'`, `payment_status='pending'`, `payment_confirmation_deadline ≈ now()+30min`; `order_items` inserted; stock **decremented**; `order_payment_events` has `created`; returns `{order_id, total_amount, deadline, store{gcash_qr_url, gcash_number, gcash_account_name}}` |
| 1.1c | Client lies about unit price (RPC must ignore it) | `total_amount` matches **server-recomputed** total from current product prices + ₱100 |
| 1.1d | Buy more than stock of a size | `P0001` ("Insufficient stock"), **full rollback** — no order row, stock untouched |
| 1.1e | Second checkout while an `awaiting_payment_confirmation` order is open (same customer) | `23505` (partial unique index) → friendly "already have a pending GCash order" |
| 1.1f | Checkout again **after** the previous order was confirmed/cancelled/expired | Succeeds (cap only applies to the open status) |
| 1.1g | Two near-simultaneous checkouts, two devices, last unit of a size | Exactly one wins; loser gets `P0001`/rollback — no double-reservation |
| 1.1h | Empty / malformed items | Rejected with a clear message |

### 1.2 `submit_gcash_proof`

| # | Case | Expect |
|---|---|---|
| 1.2a | A different customer (not the order's owner) | Denied (ownership check) |
| 1.2b | Order not in `awaiting_payment_confirmation` (already paid/cancelled) | Denied with state message |
| 1.2c | Deadline already passed | Denied — must retry checkout (order can still be swept) |
| 1.2d | Reference not 12–13 digits / non-numeric | Rejected (format CHECK + normalization) |
| 1.2e | Reference already used on **another** order (platform-wide) | `23505` → "reference already used" (NOT mislabeled as double-submit) |
| 1.2f | Double-submit the **same** order (same or different ref) | One proof per order (`order_id UNIQUE`) → second fails cleanly |
| 1.2g | Screenshot path not under `{order_id}/` | Rejected |
| 1.2h | Happy path | Proof row inserted (ref + screenshot_url); **deadline extended to now()+2h**; `order_payment_events` has `proof_submitted`; `seller_notifications` row created (in-app badge) |
| 1.2i | Screenshot URL points to a non-existent object | Accepted by RPC (checked app-side); flag for storage hygiene |

### 1.3 `confirm_gcash_payment`

| # | Case | Expect |
|---|---|---|
| 1.3a | Called by the **store owner** on their own order | `status='pending'`, `payment_status='paid'`; `order_payment_events` has `confirmed` (actor = seller); customer notification created |
| 1.3b | Called by a seller who owns a **different** store | Denied (explicit ownership check, not just RLS) |
| 1.3c | Called with **no proof submitted** | Denied (proof required before confirm) |
| 1.3d | Confirm **after** the order was expired | Denied (state no longer `awaiting_payment_confirmation`) |
| 1.3e | Double-tap / two devices confirm simultaneously | Exactly one wins (guarded `UPDATE … WHERE status=…`); the other no-ops; stock unchanged (still reserved once) |
| 1.3f | Confirm an order whose stock was already oversold elsewhere | `P0001` surfaces; order stays reservable/visible — handle per product-stock behavior |

### 1.4 `reject_gcash_payment`

| # | Case | Expect |
|---|---|---|
| 1.4a | Non-owner / other-store seller | Denied |
| 1.4b | Happy path with reason | Order `cancelled`; **stock re-incremented exactly once** (compare before/after via inventory); `order_payment_events` has `rejected` with notes; customer notified with reason |
| 1.4c | Double-reject (two devices) | Second call no-ops — stock released **exactly once**, never double-released |
| 1.4d | Reject after expiry | No-op (already swept) |

### 1.6 `cancel_my_pending_gcash_checkout` (customer self-service)

| # | Case | Expect |
|---|---|---|
| 1.6a | A different customer tries to cancel someone else's order | Denied (`42501`) — ownership check inside the RPC, not just RLS |
| 1.6b | Cancel an order **with proof already submitted** | `P0001` — "wait for the store / contact the store"; stock NOT released; store can still confirm/reject |
| 1.6c | Cancel an order that already resolved (paid/rejected/expired) | Returns `false` — no-op, no stock change |
| 1.6d | Happy path (no proof) | Order `cancelled`; stock re-incremented exactly once; `order_payment_events` has `cancelled_by_customer` (actor = customer); customer notification "GCash checkout cancelled" |
| 1.6e | Cancel then immediately re-checkout (same customer, same items) | Succeeds — the partial unique index cap was freed by the cancel; stock available again |
| 1.6f | Double-cancel (two devices) | Second call no-ops — stock released exactly once |
| 1.6g | Cancel an expired-but-not-yet-swept order | Succeeds (status still `awaiting_payment_confirmation`) — resolves it early instead of waiting for the sweep |

### 1.5 `expire_overdue_gcash_orders`

| # | Case | Expect |
|---|---|---|
| 1.5a | Order past deadline, no proof | Cancelled; stock released exactly once; `expired` event; customer notified "retry checkout" |
| 1.5b | Order past deadline **with proof submitted** (deadline already extended +2h) | Not expired until the extended deadline — a paid-but-unconfirmed order is never expired out from under the customer |
| 1.5c | Run twice (idempotency) | Second run expires nothing, releases nothing — no double-release |
| 1.5d | Run while a seller is confirming at nearly the same moment | Exactly one final state — guarded transition wins the race |

---

## 2. Flutter manual E2E (after RPC tests pass)

| # | Scenario | Steps | Expect |
|---|---|---|---|
| 2.1 | Happy path | Customer checkout → GCash → pays seller → submits ref + screenshot → seller taps Confirm | Order Confirmed → tracking shows `pending` → stock decremented exactly once; customer sees normal pipeline |
| 2.2 | Proof only | Customer submits proof, seller hasn't acted | Pay screen shows "waiting for seller"; tracking shows the new status with countdown; dashboard card shows the order |
| 2.3 | Rejection | Seller taps Reject + reason | Order `cancelled`; customer tracking shows cancelled with the seller's reason; stock restored; customer can checkout the same items again |
| 2.4 | Expiry | Let the 30-min deadline lapse (no proof) | Order expires; stock restored; customer notified; dashboard card drops the order; seller can no longer confirm |
| 2.5 | Resume | Customer closes the pay screen, reopens tracking | "Pay via GCash again" button returns to `GcashPayScreen` with the same order/deadline (if no proof yet) |
| 2.6 | Second checkout blocked → dialog | Customer with an open awaiting order taps Complete Order | **Resolution dialog** appears: Order # · total · time left. "Complete Payment" resumes the pay screen; "Cancel Pending Order" (confirm) cancels + **auto-retries** the new checkout; "Not Now" dismisses |
| 2.6b | Dialog when proof already submitted | Same scenario but the pending order has proof | Dialog shows "Track My Order" only (no Cancel) — cancel is money-safe-blocked |
| 2.6c | Cancel → fresh checkout | Customer cancels via the dialog | Stock restored; new order created for the same items; no dead-end |
| 2.7 | Screenshot required | Try to submit without picking a screenshot | Blocked by the form (upload is required) |
| 2.8 | Cart state | After GCash order creation | Cart is cleared; re-adding the same items then checking out again hits 2.6 until the first order resolves |
| 2.9 | Cash on Pickup | Regression | Completely unchanged flow, still `createOrder()` |

---

## 3. Security / RLS checks

| # | Check | Expect |
|---|---|---|
| 3.1 | Customer A reads customer B's `gcash_payment_proofs` | 0 rows (SELECT own-only) |
| 3.2 | Seller of store A reads proofs for store B's orders | 0 rows |
| 3.3 | Customer tries to UPDATE `gcash_payment_proofs` / `order_payment_events` directly | Denied (no write policies) |
| 3.4 | Client tries to `UPDATE orders SET payment_status='paid'` directly (non-admin) | Denied — tightened store-scoped policy; only `confirm_gcash_payment` sets `paid` |
| 3.5 | Seller of store A tries to UPDATE an order row belonging to store B | Denied (store-scoped policy) |
| 3.6 | Signed URL for a proof screenshot issued to a non-owner | Fails (bucket private, object policies scope reads to the order's customer/seller) |
| 3.7 | `order_payment_events` is append-only | No client insert/update/delete possible; history intact after a dispute |

---

## 4. Regression checks

| # | Check | Expect |
|---|---|---|
| 4.1 | Product ratings / reviews flow | Unaffected |
| 4.2 | POS GCash flow (`pos_screen.dart`) | Untouched, still works |
| 4.3 | Cash-on-pickup online checkout | Untouched |
| 4.4 | Order status notifications | **Should now work** (the `notifications.order_id` BIGINT→UUID fix) — confirm a status change produces an in-app notification for the customer |
| 4.5 | `order_status_history` rows still written on status changes | Yes (conditional column fix keeps the trigger happy) |

---

## 5. Rollout notes

- Soft-rollout suggestion: watch one store's first few direct-GCash orders before
  advertising the flow; every payment is seller-confirmed so a mistake is visible in
  the queue, not silent.
- No secrets/env vars to manage — nothing to rotate, no webhook endpoint to register.
