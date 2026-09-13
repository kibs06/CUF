# Bulk Reservations (Reseller Holds) — Architecture

> **Status:** Implemented (app code complete; the SQL migrations must be
> applied via SQL Editor — see §8). This document is the source of truth for
> the feature's design. Last updated: Sep 13, 2026.
>
> ⚠️ **DEPOSIT GATE ADDED (Sep 13, 2026)** — the lifecycle below gained a
> financial commitment step between seller approval and the stock draw:
> `pending → awaiting_deposit → approved(reserved) → fulfilled`. Seller
> approval now only opens a 24-hour GCash deposit window (20% of the
> estimated value, resolved and stored at approval); **stock is drawn only
> when the store owner confirms the customer's deposit proof** (direct-GCash
> pattern, `bulk_reservation_deposits` table). Cancelling/expiring a paid
> hold forfeits the deposit (non-refundable); expiry of an unpaid window
> never touches stock. See `20260913130000_add_bulk_reservation_awaiting_deposit_status.sql`,
> `20260913140000_add_bulk_reservation_deposits.sql`, and the pgTAP suite
> `supabase/tests/bulk_reservation_deposits.test.sql`.

## 1. Concept

A **bulk reservation** is a reseller hold: a customer asks a seller to set
aside a large quantity of a product ("I want 50 pairs to resell"), the seller
approves with a deadline, and the units are **physically moved out of
`inventory.stock` into the hold** so no other buyer can purchase them. The
hold resolves exactly once — fulfilled (seller marks picked up/paid),
cancelled (customer), rejected (seller), or expired (deadline sweep).

Crucially, a reservation is **not an order**. No money moves, no
`orders`/`order_items` rows are written, and revenue charts are unaffected.
Fulfillment is currently a manual seller action (release + notification);
recording an actual sale at pickup is a known future extension.

**Design choice — total-stock holds:** the hold is against the product's
TOTAL stock, not specific sizes. Resellers buy mixed batches; `requested_sizes`
records the customer's desired split for the seller's reference, and the stock
draw at approval takes units from whatever sizes have stock.

## 2. Lifecycle

```
                 request_bulk_reservation()      decide_bulk_reservation()
  [customer] ───────────────────────────────▶ pending ────────────────────┐
                                             (no stock held)               │
                                     ┌──────────────├────────────┐         │ approve(days)
                              reject │      cancel │   expire │           ▼
                                     ▼             ▼          ▼   awaiting_deposit (24h window,
                                 rejected    cancelled     expired     NO stock held)
                                 (terminal)  (terminal) (terminal)    ├───▶ approved/reserved (stock
                                                                  │         drawn on deposit confirm)
                     submit proof → seller confirm ───────────────┤      ├───▶ fulfilled (seller)
                     (deadline passes unpaid → expired,           │      ├───▶ cancelled (customer;
                     no stock ever drawn)                         └───▶   deposit FORFEITED if paid)
                                                            expired (sweep; forfeits paid deposit)
```

- **pending** — request exists, zero stock impact.
- **awaiting_deposit** — seller approved and opened a 24-hour GCash deposit
  window (`deposit_amount` = ceil(20% × price × quantity), stored resolved at
  approval). ZERO stock impact — inventory is untouched until the deposit is
  confirmed. The customer submits a proof (12–13-digit GCash reference +
  screenshot into the private `payment-proofs` bucket under `{reservation_id}/`);
  the store owner verifies it in their GCash app and confirms. The deadline
  passing unpaid expires the row without ever touching stock.
- **approved ("reserved" in the UI)** — the seller's confirm drew the stock
  (same largest-first, `FOR UPDATE` loop that approval used to run). The
  seller's chosen hold window (`expires_at`, set at approval) becomes operative
  only here. **Deposit is non-refundable from this point**: cancelling or
  expiring forfeits it (`deposit_status = 'forfeited'`) and releases the stock.
- **release (cancelled/expired)** — units returned to inventory one at a
  time, lowest-stock sizes first; if the product's inventory rows vanished,
  remainder lands in a `('Restock', n)` row so units are never lost.
- **fulfilled** — hold released as sold goods; the paid deposit is recorded
  as applied toward the (still-unbuilt) eventual sale (no sale recorded yet —
  see §1).

Exactly-once guarantee: every state-changing RPC re-checks the row's current
status under `FOR UPDATE` and raises `ALREADY_RESOLVED`/`ALREADY_DECIDED` if it
already moved on (mirrors the direct-GCash order RPC pattern in
`20260808210000_add_direct_gcash_rpcs.sql`).

## 3. Database (`20260913120000_add_bulk_reservations.sql` + deposit gate `20260913140000_add_bulk_reservation_deposits.sql`)

**Table `public.bulk_reservations`:**

| Column | Notes |
|---|---|
| `id`, `customer_id`, `store_id`, `product_id` | UUIDs; CASCADE deletes |
| `quantity` | requested units, CHECK > 0 |
| `reserved_stock` | units physically held; 0 until the deposit is confirmed |
| `requested_sizes` | JSONB array `[{size, quantity}]` — informational |
| `note` | customer's message to the seller |
| `status` | enum `bulk_reservation_status`: pending/awaiting_deposit/approved/rejected/cancelled/expired/fulfilled |
| `deposit_amount` | resolved deposit owed — ceil(20% of price × quantity) at approval; null before approval |
| `deposit_status` | `not_required` (default) / `unpaid` / `paid` / `forfeited` / `refunded` (reserved for a future seller refund flow; no RPC sets it yet) — CHECK-constrained text |
| `deposit_deadline` | 24h from approval; passing it expires the row with zero stock movement |
| `deposit_paid_at` | stamped at the seller's deposit confirm (== `reserved_at`) |
| `deposit_proof_id` | FK to the accepted `bulk_reservation_deposits` row (the brief's `deposit_gcash_intent_id` assumed the PayMongo flow; the approved design links the direct-GCash proof instead) |

**Table `public.bulk_reservation_deposits`** (new): one proof per reservation
(UNIQUE), platform-wide UNIQUE 12–13-digit `reference_number`, `screenshot_url`
into the private `payment-proofs` bucket under `{reservation_id}/…` (four
storage policies mirror the order-proof ones, folder-name based), `submitted_by`
audit. SELECT RLS: the reservation's customer, the store's owner, admins. **No
write policies** — submissions only via the SECURITY DEFINER RPC.
| `expires_at` | set at approval: `now() + make_interval(days => p_days)` |
| `reserved_at` / `released_at` / `fulfilled_at` | exactly-once audit stamps |
| `rejection_reason` | shown to the customer |

RLS: customer SELECT/INSERT own rows; seller (store `owner_id`) SELECT own
store's rows; admin SELECT all. **No UPDATE policy** — every state change goes
through SECURITY DEFINER RPCs.

**RPCs (all SECURITY DEFINER, granted to `authenticated` only):**

| RPC | Actor | Purpose |
|---|---|---|
| `request_bulk_reservation(product, store, qty, sizes, note)` | customer | Validates live stock + one-live-request-per-customer-per-product, inserts pending row, notifies seller |
| `decide_bulk_reservation(id, approve, days, reason)` | seller (owner) | Reject → terminal + reason. Approve → opens the customer's 24-hour deposit window: stores `deposit_amount` (ceil 20% of estimated value), `deposit_deadline`, `deposit_status='unpaid'`, `expires_at` (operative only after the deposit). NO stock moves. Notifies customer that a deposit is due |
| `submit_bulk_reservation_deposit_proof(id, ref, screenshot)` | customer | Direct-GCash proof pattern: validates ownership/state/deadline/reference format/screenshot folder, one proof per reservation, platform-wide reference dedupe (incl. order proofs). No status flip, no stock movement |
| `confirm_bulk_reservation_deposit(id)` | seller (owner) | **The security control** — verifies proof exists + deadline, then runs the relocated stock draw (largest-first, `FOR UPDATE`), sets `approved`/`reserved_stock`/`deposit_status='paid'`/`deposit_proof_id`. Aborts loudly (`INSUFFICIENT_STOCK_MISSING_<n>`) if stock shrank below quantity |
| `reject_bulk_reservation_deposit(id, reason)` | seller (owner) | Proof invalid / unverifiable → terminal `rejected`, no stock was ever drawn, deposit stays `unpaid` |
| `cancel_bulk_reservation(id)` | customer | Pending/awaiting_deposit → cancelled (no stock, no forfeiture). Approved (paid) → cancelled, stock released exactly once, `deposit_status='forfeited'` (non-refundable). Notifies seller |
| `fulfill_bulk_reservation(id)` | seller (owner) | Approved (paid) → fulfilled; releases hold; deposit recorded as applied toward the (deferred) eventual sale. Notifies customer |
| `expire_bulk_reservations()` | any authenticated | Idempotent sweep, TWO separate branches: `awaiting_deposit AND deposit_deadline <= now()` → expire, NO stock release, deposit stays `unpaid`; `approved AND expires_at <= now()` → release stock, deposit `forfeited`. `FOR UPDATE SKIP LOCKED`. Returns count |
| `_release_bulk_reservation_stock(id, expected, new, deposit_outcome?)` | private | Shared exactly-once release core (see §2); the 4th arg records the deposit outcome — `forfeited` for paid holds, NULL to leave the deposit state as-is (never conflates the two release reasons) |
| `reserved_stock_for_product(product_id)` | read helper | Sum of active holds (STABLE) — unchanged: only `approved` rows hold stock, so `awaiting_deposit` correctly contributes 0 |

**Error contract:** RPCs `RAISE EXCEPTION` with stable short codes —
`NOT_AUTHENTICATED`, `INVALID_QUANTITY`, `PRODUCT_NOT_FOUND`,
`INSUFFICIENT_STOCK`, `RESERVATION_ALREADY_EXISTS`, `INVALID_DEADLINE`,
`ALREADY_DECIDED`, `ALREADY_RESOLVED`, `FORBIDDEN`, `NOT_FOUND`,
`INSUFFICIENT_STOCK_MISSING_<n>`, and the deposit codes `DEPOSIT_DEADLINE_PASSED`,
`DEPOSIT_PROOF_REQUIRED`, `DEPOSIT_ALREADY_SUBMITTED`, `INVALID_PROOF_REFERENCE`,
`INVALID_PROOF_SCREENSHOT`, `REFERENCE_ALREADY_USED`. `friendlyReservationError()`
in the service maps ALL of them to customer-readable strings.

**Notification enum:** the `notification_category` Postgres enum gains
`'reservations'` — in its OWN migration
(`20260913110000_add_reservations_notification_category.sql`) because
`ALTER TYPE ... ADD VALUE` cannot be *used* in the same transaction that adds
it. The Dart `NotificationCategory.reservations` mirrors it
(`lib/models/notification_category.dart`, `_parseCategory` in
`app_notification.dart`, icon/color cases in `notifications_screen.dart`).

## 4. Expiry sweep — no pg_cron

This database has **no pg_cron** (see `20260907000000_fix_stale_pending_gcash_intents.sql`).
Like the GCash expiry, the sweep is **opportunistic**: the Flutter app calls
`ReservationService.expireStaleReservations()` (which invokes
`expire_bulk_reservations()`) on every load of the customer's My Reservations
screen and the seller's queue screen. Failures are swallowed (debug-print only)
since any later call finishes the job — the sweep is idempotent.

## 5. Flutter layer

**Service — `lib/services/reservation_service.dart`**
- `BulkReservation` model: parses rows with nested joins
  (`products(name, stores(name), product_images(...))` for the customer side,
  `products(name), profiles(name)` for the seller side). Helpers: `isPending`,
  `isApproved`, `isTerminal`, `statusLabel`.
- `ReservationService.instance` singleton wrapping the RPCs + two SELECT
  queries (`fetchMyReservations`, `fetchStoreReservations`,
  `fetchPendingCount` for the dashboard metric).
- `friendlyReservationError(Object)` — maps the Postgres error codes above.

**Customer UI**
- `lib/screens/customer/widgets/bulk_reservation_sheet.dart` — bottom sheet
  opened from the product detail screen's *"Buying to resell? Request a bulk
  hold"* link (below the Quantity stepper; only when total stock > 0).
  Quantity stepper capped at live stock, auto-generated size breakdown
  (largest-stock-first split of the requested quantity), estimated value,
  optional note. Discloses the 20% non-refundable deposit up front.
- `lib/screens/customer/bulk_deposit_pay_screen.dart` — deposit payment,
  reusing the direct-GCash payment UX (static QR, exact-amount card, 24h
  countdown, reference + screenshot proof form, mandatory NON-REFUNDABLE
  warning before payment).
- `lib/screens/customer/my_reservations_screen.dart` — the customer's holds
  (status chips, deposit countdown + "Pay Deposit" action on
  `awaiting_deposit` rows, forfeiture-aware cancel confirm). Reached from
  **Profile → My Reservations** (`lib/screens/shared/profile_screen.dart`).

**Seller UI**
- `lib/screens/seller/reservation_requests_screen.dart` — the queue:
  filter chips (All/Pending/Active/Resolved), tiles with requested size split
  + note + countdown, **Approve & request deposit** (deadline picker:
  1/3/7/14/30 days), **Decline** (reason sheet), **Verify Deposit Payment**
  (proof review sheet), **Mark Fulfilled**.
- `lib/screens/seller/widgets/deposit_proof_review_sheet.dart` — seller's
  proof verification: expected deposit amount, reference, signed-URL
  screenshot, Confirm (draws stock) / Reject (terminal) actions.
- `lib/screens/seller/seller_dashboard_screen.dart` — "BULK RESERVATIONS"
  metric card (pending + proof-verification count via `fetchPendingCount`,
  non-fatal on error) + alert chip when > 0, both routing to the queue.

## 6. Deliberate non-goals / known gaps

- **No sale recorded on fulfill** — revenue charts and order history don't
  include reseller pickups yet. Natural extension: a convert-to-POS-sale RPC.
- **Checkout doesn't read reservations** — other customers are protected
  because held units are *gone from `inventory.stock`*, which every stock
  check already reads. `reserved_stock_for_product()` exists for future
  availability displays.
- **No bulk pricing tiers** — quantity discounts are a separate feature.
- Sold counts (`units_sold`) do **not** include fulfilled reservations.

## 7. Testing notes

- Analyzer clean; full suite green (558 tests — 545 pre-deposit + 13 new
  model/error tests in `test/services/reservation_service_test.dart`).
- **pgTAP suite (new): `supabase/tests/bulk_reservation_deposits.test.sql`**
  (51 assertions, run by CI's supabase-migrations job) covers: approve →
  awaiting_deposit → submit proof → confirm → reserved (stock drawn
  largest-first, deposit = ceil(20%)); deadline passes unpaid → sweep expires
  with zero stock movement; pay/confirm after deadline → `DEPOSIT_DEADLINE_PASSED`;
  cancel while awaiting_deposit (no forfeiture) vs while reserved (forfeit +
  stock restore); double confirm → `ALREADY_RESOLVED`; stock bought between
  approval and payment → `INSUFFICIENT_STOCK_MISSING_<n>` without a silent
  `reserved` flip; `reserved_stock_for_product` ignores awaiting_deposit rows.
- End-to-end smoke test (two accounts): request → verify stock unchanged
  while pending → approve (stock STILL unchanged; deposit window opens) →
  customer submits deposit proof in **My Reservations → Pay Deposit** →
  seller **Verify Deposit Payment** → confirm → stock drops and status is
  Reserved → cancel (stock restores, deposit shown as forfeited). The unpaid
  sweep can be tested by approving, forcing `deposit_deadline` into the past
  in SQL Editor, and calling `SELECT expire_bulk_reservations();`.

## 8. Deployment status ⚠️

The FOUR migrations are **written but not yet applied** to the live DB (the
stored DB password in `backup/config.ps1` no longer authenticates on the
pooler, and the direct IPv6-only host is unreachable from the dev machine —
matching how the T3 migrations were applied "via SQL Editor" per
`supabase/MIGRATIONS_LIVE_STATUS.md`):

1. `supabase/migrations/20260913110000_add_reservations_notification_category.sql`
2. `supabase/migrations/20260913120000_add_bulk_reservations.sql`
3. `supabase/migrations/20260913130000_add_bulk_reservation_awaiting_deposit_status.sql`
4. `supabase/migrations/20260913140000_add_bulk_reservation_deposits.sql`

Apply IN THAT ORDER (the enum-value migrations must commit before the RPC
migrations that use the new values). All are idempotent (safe to re-run).
After applying, update `supabase/MIGRATIONS_LIVE_STATUS.md`. Until applied,
the app surfaces friendly "something went wrong" errors from the RPC calls.
