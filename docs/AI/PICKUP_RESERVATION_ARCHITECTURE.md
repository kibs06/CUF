# Pickup Reservations (Small FREE Holds) — Architecture

> **Status:** Implemented (app code complete; the SQL migration must be applied
> via SQL Editor — see §10). Last updated: Sep 15, 2026.
>
> **Scope:** ANQUI checklist item **#14 — "Reserve for pick up (expire the
> reservation for 24 hours)"**. Client decision: a small (1–2 pair) customer
> pickup hold is **FREE** — no deposit, no approval; the stock is simply
> released if it is not collected within 24 hours.

## ⚠️ 0. Read this first: there are TWO reservation systems

They are **not** variants of each other, and nothing in either one may be
reused by the other beyond the two items listed below. If you are about to add
"just a small deposit" here, or "just a fast path" there, stop — the deposit
and the approval step are what the bulk flow *is*.

| | `bulk_reservations` (reseller holds) | `pickup_reservations` (this system) |
|---|---|---|
| Audience | reseller, ~50 pairs | walk-in customer, 1–2 pairs |
| Approval | seller approves first | **instant — no approval, no waiting** |
| Money | 20% **non-refundable GCash deposit** | **free** — no money, no deposit table |
| States | 8 (`pending → awaiting_deposit → approved → fulfilled` + `rejected`/`cancelled`/`expired`) | 4 (`active` → `fulfilled`/`cancelled`/`expired`) |
| Deadline | chosen by the seller at approval | **fixed, 24 h** |
| Stock held | against the product's **total** stock, drawn across sizes | against **one size** |
| Order written? | no (fulfilment is a manual release) | **yes** — becomes a real POS order |

They share exactly **two** things and nothing else:

1. `inventory.stock` — the place a hold physically lives (units are moved
   *out* of it). Same mechanism, deliberately: it is the only availability
   number the app reads, so a size held to 0 is genuinely unbuyable by
   everyone else.
2. The `reservations` **notification category** (reused, not re-created).

`pickup_reservations` never reads, writes or depends on `bulk_reservations` or
`bulk_reservation_deposits`. A deposit or an approval step appearing in this
flow is a **bug**.

## 1. Concept

A **pickup reservation** is a free, short-lived hold on 1–2 units of one size
of one product, so a customer can walk to the store knowing the pair is
waiting. It resolves exactly once: **fulfilled** (the customer arrives and the
seller records the sale), **cancelled** (customer or seller, stock released
immediately), or **expired** (the 24 h deadline passed and the sweep released
the stock).

**The cap is 2 per hold** (`public.pickup_reservation_max_quantity()`), taken
from the checklist's own "1–2 pairs" framing. Above the cap the answer is not
"no" but "use the other flow": the RPC raises `ABOVE_PICKUP_CAP` and the sheet
points the customer at the bulk request, rather than letting them submit
something the server will reject.

The cap lives in **one** place — a SQL function — and every consumer reads that
one number: the RPC, the pgTAP suite, and the Dart constant
(`PickupReservation.maxQuantity`), which a contract test
(`test/services/pickup_reservation_contract_test.dart`) pins to the SQL. Four
copies of "2" is how the cap silently drifts.

## 2. Lifecycle

```
                       request_pickup_reservation()          fulfill_pickup_reservation()   [seller]
  [customer] ─────────────────────────────────────▶ active ─────────────────────────────▶ fulfilled
  (1–2 units, one size)   stock DECREMENTED at              │   becomes a POS order
                          creation, deadline = +24h         │   (no second stock draw)
                                                           │
                      extend_pickup_reservation()  ────────┤   +24h, ONCE, only while live
                      (customer, before it lapses)         │   stock untouched, reminder re-armed
                                                           │
                                                           ├── cancel_pickup_reservation()   [customer
                                                           │   or seller] → cancelled  ✔ stock released
                                                           └── expire_pickup_reservations()  [sweep]
                                                               → expired  ✔ stock released
```

**The hold window is bounded on purpose.** A free hold should survive "I am on
my way but I will not make 6pm" — and it must never become a way to park a
store's stock indefinitely. So a hold runs `pickup_reservation_hold_hours()`
(24 h) and may be extended `pickup_reservation_max_extensions()` times (once),
by `pickup_reservation_extension_hours()` (24 h) each: **at most 48 hours from
reservation, ever**. See §5 for the three rules and the CHECK that enforces the
ceiling.

- **active** — units are out of `inventory.stock`. There is no `pending`: a row
  exists only *because* stock was held.
- **fulfilled** — converted into an order with `source = 'pos'`,
  `status = 'received'`, `payment_status = 'paid'`. See §5 for why that is the
  POS path and not online checkout.
- **cancelled** / **expired** — stock returned to `inventory.stock`, exactly
  once (§4).

## 3. Schema — `public.pickup_reservations`

| Column | Notes |
|---|---|
| `id` | uuid pk |
| `customer_id` | → `profiles`, cascade |
| `store_id` | → `stores`, cascade. Denormalised from the product so the "incoming reservations for my store" query is a single-table read |
| `product_id` | → `products`, cascade |
| `size` | **size-specific**, unlike a bulk hold — `inventory` and `order_items` are both keyed `(product_id, size)`, so the hold matches how stock and sales are keyed everywhere |
| `quantity` | `CHECK (quantity > 0)`; capped at 2 by the RPC |
| `reserved_stock` | units physically taken out of `inventory.stock`. Positive on every `active` row |
| `status` | enum `pickup_reservation_status`: `active`/`fulfilled`/`cancelled`/`expired` |
| `pickup_deadline` | `reserved_at + 24 h` |
| `reserved_at` / `released_at` / `fulfilled_at` | exactly-once audit stamps |
| `fulfilled_order_id` | the POS order this became. `ON DELETE SET NULL`, not cascade: deleting the order must not delete the reservation's history |
| `reminder_sent_at` | makes the T-2h reminder exactly-once. **Cleared by an extension**, because the new deadline is owed its own warning |
| `extension_count` | `0..max_extensions`. Stored rather than derived so the cap is auditable on the row itself |

Indexes: `(store_id, status)`, `(customer_id, created_at DESC)`, plus two
partial indexes on `pickup_deadline` scoped to `status = 'active'` —
only `active` rows can ever be picked up by either sweep.

**Two CHECK constraints make the promised patience structural**, so no code path
— present or future — can exceed it:

- `pickup_reservations_within_max_window` — `pickup_deadline <= created_at +
  hold_hours × (1 + max_extensions)`, i.e. the **48 h ceiling**. Both functions
  are `IMMUTABLE` constants, which is what makes them usable in a CHECK; if
either number is ever changed, existing rows are *not* re-validated, so it is a
  data-affecting change rather than a config tweak.
- `pickup_reservations_within_extension_cap` — `extension_count <= max_extensions`.

**The migration CONVERGES this table; it does not merely create it (§3b).**
`CREATE TABLE IF NOT EXISTS` is a **no-op** on an existing table, so a column
that lives only inside it is invisible on any database that already holds the
table. This file is applied by hand through the SQL Editor (see
`supabase/MIGRATIONS_LIVE_STATUS.md`), which makes that a live hazard rather
than a theoretical one: re-applying it over a `pickup_reservations` created by
the **pre-extension revision of this same file** died on

```
ERROR: 42703: column "extension_count" does not exist
```

…raised by the `pickup_reservations_within_extension_cap` constraint below —
i.e. naming a statement whose own text is correct. §3b therefore lists all 16
columns again as `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, so re-applying the
file converges a table created by ANY earlier revision of itself. Two guards
keep the two lists from drifting: `test/services/pickup_reservation_contract_test.dart`
asserts §3 and §3b declare the same columns *and* that §3b still runs before
the constraints that read it, and the pgTAP suite pins the live table's column
set. (`ADD COLUMN IF NOT EXISTS` matches on NAME only, so this reconciles
missing columns — not changed ones — and, like the CHECKs, existing rows are
not re-validated.)

**One live hold per customer per product+size — enforced by the database, not
just by the RPC.** A partial unique index on
`(customer_id, product_id, size) WHERE status = 'active'` backstops the RPC's
own duplicate check, which is **serial**: two simultaneous submits both see "no
active hold" and both insert. The stock compare-and-set still stops them
overselling, so the symptom is only a duplicate hold — which is precisely why
it would have gone unnoticed. The loser now gets `23505` and the whole RPC
statement rolls back (stock included — it is one statement from the client's
point of view); the Dart service maps `23505` to the *same* copy as the RPC's
`RESERVATION_ALREADY_EXISTS`, from one shared constant so the two paths cannot
drift. Partial on `status = 'active'` so a resolved hold never blocks a new
one; exact on `size`, while the RPC's own check stays deliberately fuzzy
("41" vs "US 41") for the sequential near-duplicate case.

**RLS: `SELECT` only** for three audiences (the customer's own rows; the store
owner's rows; admins via `is_admin()`). There is deliberately **no**
`INSERT`/`UPDATE`/`DELETE` policy. Every row represents stock that has already
been taken, so a client-side `INSERT` could mint a hold-shaped row that holds
nothing — and an `UPDATE` could move a row to `cancelled` without the release
ever running. The RPCs are the only write path, which is also what makes the
cap and the stock check unbypassable by a hand-crafted request.

## 4. The hold mechanism — and the one invariant not to break

Requesting **decrements** `inventory.stock` for the reserved size with a
`stock >= quantity` **compare-and-set** (so two simultaneous requests cannot
oversell), inside the same transaction that inserts the row. Release
(cancel / expire) **increments** it back.

> **THE INVARIANT: the hold IS the draw.**
> At fulfil the order is written but `inventory` is **not touched again** — the
> units left `inventory.stock` when the hold was created, so decrementing again
> would double-draw them. Verified while building this: `order_items` has **no**
> triggers in this schema, so nothing decrements on order insert. If a
> decrement trigger is ever attached to `order_items`,
> `fulfill_pickup_reservation` must change to release-then-draw, and the pgTAP
> suite asserts the current behaviour so that change cannot happen silently.

**Exactly-once release.** Cancel and the expiry sweep both funnel through one
core, `_release_pickup_reservation_stock(id, expected_status, new_status)`,
which re-reads the row `FOR UPDATE` and **no-ops if the status has already
moved on**. That is what makes the sweep idempotent and what makes the
sweep-vs-manual-cancel race safe: whoever wins the lock releases; the loser
returns `false` and does nothing. The sweep additionally uses
`FOR UPDATE SKIP LOCKED` so two concurrent sweepers never block each other.

`public.pickup_reserved_stock_for_product(p_product_id, p_size?)` reports units
currently held by *pickup* holds. Note the deliberate distinction from
`reserved_stock_for_product()`, which reports *bulk* holds: **both are already
reflected in `inventory.stock`**, so neither may be subtracted from it. They
explain where stock went; they are not a second availability number.

## 5. RPCs

All `SECURITY DEFINER`, `SET search_path = public`, granted to `authenticated`
only (`anon` has no `EXECUTE`).

| RPC | Who | Does |
|---|---|---|
| `request_pickup_reservation(p_product_id, p_size, p_quantity = 1) → uuid` | customer | validates the cap (`ABOVE_PICKUP_CAP`) and live stock, decrements it, inserts `active` with `pickup_deadline = now() + 24 h`, notifies the customer **and the store owner**. One active hold per (customer, product, size): the serial attempt raises `RESERVATION_ALREADY_EXISTS`, and a *concurrent* one is stopped by the partial unique index (`23505`), stock and all |
| `extend_pickup_reservation(p_reservation_id) → timestamptz` | customer **only** | asks for more time; returns the new deadline. See the rules below |
| `cancel_pickup_reservation(p_reservation_id) → uuid` | customer **or** store owner | releases the stock immediately, `status = 'cancelled'`, notifies the counterparty |
| `fulfill_pickup_reservation(p_reservation_id, p_payment_method = 'cash') → uuid` | store owner | "customer arrived" — writes the POS order and marks `fulfilled` |
| `expire_pickup_reservations() → integer` | anyone signed in (opportunistic) | the sweep; returns how many it expired |
| `send_pickup_reservation_reminders() → integer` | anyone signed in (opportunistic) | the T-2h reminders; returns how many it sent |

**Why fulfil writes a POS sale, not an online order.** `orders.fulfillment` is
currently hardcoded to `'pickup'` and the delivery branch is effectively dead
(`DELIVERY_FEE_AND_MAP_ARCHITECTURE.md` §71/95/102), so pickup is the only real
fulfilment path. Payment happens **at the counter**: the seller confirming
handover *is* the statement that money changed hands, so the order is written
with `status = 'received'`, `payment_status = 'paid'`, `source = 'pos'`, and a
seller-chosen method (cash by default, GCash allowed). This deliberately does
**not** route through the online checkout/GCash-proof flow — there is no
customer-side payment to verify.

### The three extension rules

A hold may be extended only when **all three** hold, and each is enforced in the
RPC (and, for the cap, twice over):

1. **Only the customer.** The store cannot extend on the customer's behalf —
   that is the store choosing to keep its own stock off the shelf, which is
   what the bulk reservation flow is for. A seller calling this gets `FORBIDDEN`.
2. **Only before it expires.** Once `pickup_deadline` has passed, the hold may
   lapse at any moment (the sweep has not necessarily run yet), so promising
   more time would promise stock nobody can guarantee. `HOLD_LAPSED`.
3. **Only `max_extensions` times**, each buying one ordinary window,
   `EXTENSION_LIMIT_REACHED` beyond that — and the 48 h ceiling is a table CHECK,
   not just this branch.

The `UPDATE` is `FOR UPDATE`, which is what makes the cap concurrency-safe: two
simultaneous taps serialize, and the second sees `extension_count` already
incremented and is refused — the same class of race as the duplicate-hold index.
**Stock is not touched**: the units left `inventory.stock` when the hold was
created, and more time does not change that. Nothing is charged, because a hold
is free and so there is nothing to re-authorize.

## 6. Expiry sweep and reminders

**There is no `pg_cron` in this database** (see
`20260907000000_fix_stale_pending_gcash_intents.sql`), so this is the same
**opportunistic** sweep pattern the bulk flow uses: the app calls it when the
reservations screens open, and any later call finishes the job.

- `expire_pickup_reservations()` — `status = 'active' AND pickup_deadline <= now()`
  → `expired` + stock released, via the shared core.
- `send_pickup_reservation_reminders()` — `active`, `reminder_sent_at IS NULL`,
  `pickup_deadline` within the next **2 hours**. It **stamps
  `reminder_sent_at` first** and `CONTINUE`s if another caller already claimed
  the row, so a duplicated concurrent call cannot send the reminder twice.

Notifications, all under the existing **`reservations`** category:

| When | Who | Text |
|---|---|---|
| On request | customer | item, size, store, deadline |
| On request | store owner | a hold came in |
| On extend | customer | "Pickup hold extended" + the new deadline, and "That was your last extension" when the cap is spent |
| On extend | store owner | "A customer extended a hold … to <deadline>" — the commitment grew, so it is told |
| T-2h | customer | "Your pickup hold expires soon" + deadline — **one per hold** |
| T-2h | store owner | "2 pickup holds expire in the next 2 hours — 2 pairs return to stock unless collected." — **one per batch** |
| On expiry | customer | hold released |
| On expiry | store owner | stock is back available |
| On cancel | counterparty | the hold is off |
| On fulfill | customer | collected, with the order id |

**Why the two sides get different shapes.** The customer has one decision about
one specific pair, so they get a notification per hold. A store with twenty
holds must not receive twenty notifications, and what a seller can act on is the
*batch* — which holds lapse and how much stock comes back. So the store gets a
single aggregated summary per owner per sweep run, counting only the rows **that
run** claimed.

The aggregate inherits its exactly-once property from the same per-row
`reminder_sent_at` stamp: a second sequential run claims nothing and therefore
sends no summary. (Two *concurrent* runs each claim a disjoint subset of rows and
so each summarise their own share — bounded by the number of runs, and never a
duplicate row. That is the accepted trade for not needing a second stamp table.)

A hold on a store with **no owner** is reminded to its customer but left out of
the summary, because `notifications.user_id` is `NOT NULL` and one such row
would abort the entire sweep — taking every other store's reminders with it.
`stores.owner_id` is nullable but its FK is plain `NO ACTION`, so an ownerless
store is not reachable through the app today; this is a defensive guard, and the
pgTAP suite asserts the property by inserting that state directly. (The same
hazard still exists in `request_pickup_reservation`'s seller heads-up — see
§12.)

A hold is fulfilable for a short grace period **past** its deadline (the
customer is standing at the counter and the sweep may not have run) — but a
hold the sweep already released is **not**: those units are back on the shelf
and may be gone. Hence `fulfill` accepts `active` (any deadline) and raises
`ALREADY_RESOLVED` for anything else.

**The reminder is re-armed by an extension.** `extension_count` is per hold but
the warning is per *deadline*, so `extend_pickup_reservation` clears
`reminder_sent_at`: leaving it set would mean the customer is never told the
second deadline is close — the one warning the whole feature relies on. (A
customer can therefore be warned more than once across a hold's life, once per
deadline. That is the intent, not a duplicate.)

## 7. The step-6 decision: does a fulfilled pickup count toward `units_sold`?

**Yes — by construction, and it is the same rule the POS already used rather
than a new exception for this feature.**

`fetchUnitsSold()` sums `order_items.quantity` over paid, non-cancelled orders.
`fulfill_pickup_reservation` creates exactly such an order, so a collected
pickup appears in POS sales, revenue and `units_sold` — and therefore in Best
Sellers (item #7) and `SortMode.bestSelling` — with **no new aggregation
anywhere**. Bulk reservations still do **not** count, because they record no
sale at all.

## 8. UI

| Surface | File |
|---|---|
| **Reserve for Pickup** action on the product detail screen (quantity stepper, capped at 2 *and* at the size's live stock — the stock wins when it is lower) | `lib/screens/customer/widgets/pickup_reservation_sheet.dart` |
| "My Pickup Reservations" (countdown to the deadline, cancel, and **Extend 24h** while a hold is live and the cap is unused, with a dialog that states the store's side of the bargain) | `lib/screens/customer/my_pickup_reservations_screen.dart` |
| Seller's incoming holds ("customer arrived — fulfill", manual release, per-tile countdown, and an `extended ×N` marker so a later deadline always has an explanation) | `lib/screens/seller/pickup_reservations_screen.dart` |
| Service / models (`PickupReservation`, `PickupHoldSummary`, `PickupStoreStats`) | `lib/services/pickup_reservation_service.dart` |

### The store's early warning: `PickupHoldSummary`

The seller screen opens with a **summary band** above the filters — deliberately
there rather than inside a filter, because "what am I about to get back?" is a
question about the whole store, not about the list being viewed:

```
2 holds · 3 pairs held
2 pairs back within 2h        [Show]
```

It counts **lapsing** holds (inside the last 2 hours — the *same* window the
server's T-2h reminder uses, so the screen and the notification agree about what
"about to lapse" means) and **lapsed** ones (past the deadline, sweep not yet
run: those units really are still off the shelf, so they are counted as held, but
they are the first thing coming back). "Returning" is the sum of both — which is
the honest answer to "what is about to come back".

A matching **`Lapsing soon (N)` filter chip** appears only when there is
something in it, and narrows the list to exactly those holds, so a store can act
on the urgent ones without reading the whole list. Both are covered by widget
tests (`test/widgets/seller_pickup_reservations_test.dart`).

The seller dashboard's alert chip carries the same signal in one line
(`3 pickup holds · 2 pairs back soon`) from **one** query — `fetchStoreStats` — so
the headline count and the lapsing badge can never come from two different
snapshots. `PickupHoldSummary` is pure arithmetic over rows already in hand and
can be built from either full reservations or a partial select, with a test that
the two entry points agree.

Entry points: product detail (Reserve for Pickup, distinct from Buy Now / Add to
Cart), `Profile → My Pickup Reservations`, and the seller dashboard's alert
chip + tile.

## 9. Trusted-device gate — what it does and does not cover

`pickup_reservations` is **device-gated** like the other private account tables
(`orders`, `cart_items`, …). The migration ends with
`SELECT public.install_device_gate_policies();` — the documented procedure for
any migration that adds an RLS table, because the sweep only covers tables that
existed when it ran. Forgetting it makes the table silently open, and the pgTAP
invariant in `admin_account_security.test.sql` ("every RLS table is either
device-gated or explicitly exempt") fails the build. 27 tables are gated today.

**Measured limit, not a guess:** the gate is an **RLS** control, so it applies
to direct PostgREST table access. These RPCs are `SECURITY DEFINER` and owned by
`postgres`, who owns the table — so **they are not subject to the gate**: a
client with no device secret can still call `request_pickup_reservation`
(verified against the running stack with enforcement ON). The effect is benign
here — a customer can *create* a hold but can no longer *read* it from that
device, and the RPC itself enforces ownership — but it means "the table is
gated" does not imply "every path to the table is gated". That is a
pre-existing, generic property of the gate (it is equally true of the voucher
and order RPCs), not something this feature introduced. Closing it means adding
an explicit `device_is_trusted()` check to the top of the definer RPCs that
touch gated tables.

## 10. Deployment status

`20260915170000_add_pickup_reservations.sql` is **not yet applied live** — see
`supabase/MIGRATIONS_LIVE_STATUS.md`. Apply via SQL Editor; it is idempotent
and safe to re-run.

The device gate ships with **enforcement OFF**, so gating
`pickup_reservations` changes nothing until that switch is thrown (apply → ship
the build → `select public.set_device_enforcement(true);`).

## 11. Test coverage

| File | Assertions | Covers |
|---|---|---|
| `supabase/tests/pickup_reservations.test.sql` | 128 | happy path; **over-cap rejected**; **insufficient stock rejected**; the compare-and-set under a concurrent second request; the partial unique index (a second `active` row is `23505`, a cancelled one does not block); stock held on request and released on cancel **and** on expire **with no double-release when the sweep races a manual cancel**; a past-deadline `active` hold is expired while a live one is untouched; the sweep is idempotent when run twice; fulfil writes the order with `source='pos'` / `paid` / `received`, sets `fulfilled`, **does not double-draw inventory**, and feeds `units_sold`; the T-2h window fires once and never twice; the **store summary** (one per owner per batch, correct counts, singular wording, per-store isolation, silent on a second run, and never addressed to the customer); and the ownerless-store guard, which must not abort the sweep; and the **extension rules**: the window constants, both CHECK constraints, extend moves no stock, a second extension refused, a `created_at + 72 h` UPDATE refused by the constraint itself, only the customer may extend (not another customer, not the store, not anonymous), a lapsed hold refused, and the reminder **re-armed** so the new deadline gets its own T-2h warning |
| `test/services/pickup_reservation_contract_test.dart` | 14 | the Dart↔SQL contract: the cap constant matches `pickup_reservation_max_quantity()`, **the three window constants match their SQL functions** (following `extension_hours → hold_hours` indirection instead of trusting a literal), the 48 h ceiling is still a table CHECK, the RPC names and argument names match the migration, the service never touches the bulk tables/RPCs, and the migration stays separate from `bulk_reservations` |
| `test/services/pickup_reservation_service_test.dart` | 57 | error mapping (`ABOVE_PICKUP_CAP`, `RESERVATION_ALREADY_EXISTS`, the concurrent `23505` loser, `EXTENSION_LIMIT_REACHED`, `HOLD_LAPSED`, `INSUFFICIENT_STOCK`, `FORBIDDEN`, …), countdown formatting, the edge case that a row with no deadline must not read as "Expired", `fetchStoreStats`'s single-query shape, the whole `PickupHoldSummary` matrix (the 2-hour boundary inclusive, lapsed ≠ lapsing, resolved holds ignored, a missing quantity read as one pair, pluralisation, and the two entry points agreeing), and **the extension rules** (cap spent, lapsed refused even with the cap unused, resolved and deadline-less holds refused, an unknown `extension_count` read as none used, and `extend()`'s call shape plus a reply with no parseable deadline) |
| `test/widgets/pickup_reservation_sheet_test.dart` | 10 | the sheet: free/no-deposit copy, the size pre-selected on the detail screen, a single in-stock size needing no tap, the stepper never exceeding the cap or the live stock, larger orders pointed at bulk, and **submit inert until a size is chosen** |
| `test/widgets/seller_pickup_reservations_test.dart` | 6 | the store's band and filter: the counts, nothing rendered when nothing is lapsing, a lapsed hold counted as coming back, the chip and the band's *Show* both narrowing to the urgent holds, and resolved holds neither counted nor offered |
| `test/widgets/my_pickup_reservations_test.dart` | 7 | the customer's extension action: offered on a live hold with the amount of time named, withdrawn once extended and once lapsed, the dialog naming the store's side, confirming calls the RPC and reports the new deadline, backing out asks for nothing, a refusal reads as copy, and a resolved hold offers neither action. (A lapsed hold still carries the `Extend 24h` *label*, which is what gives this file teeth against the screen dropping its own gate.) |

Verified: **844** Flutter tests pass, `flutter analyze` clean, and **8 files /
358 DB assertions PASS from a clean `supabase db reset`**.

## 12. Known limitations

- **An extension cannot be undone, and a lapsed hold cannot be extended.** Once
  the deadline has passed the only routes are collection (the seller can still
  fulfil it, briefly) or a fresh reservation. The asymmetry is deliberate: the
  server cannot promise stock it may be about to release.
- **Raising the two window constants later does not retro-validate rows.** The
  CHECKs are evaluated on write, so changing `pickup_reservation_hold_hours()`
  or `pickup_reservation_max_extensions()` is a data-affecting change.
- **The extension is customer-only by design.** A store that wants to be lenient
  beyond 48 h has no tool for it; the answer to that, if it is ever asked for, is
  a store-side "hold longer" policy field, not a looser cap here.

- **The store summary is per run, not per window.** Two concurrent sweep runs
  each summarise the rows they claimed, so a seller could get two summaries for
  one window. No hold is ever counted twice.
- **`request_pickup_reservation`'s seller heads-up has the same NULL-recipient
  hazard** the reminder needed a guard for (an `INSERT ... SELECT s.owner_id`
  with no `IS NOT NULL`). Unreachable today for the same reason (an ownerless
  store is not creatable through the app), but it would abort the *request*
  rather than a sweep, so it is worth the same one-line guard if
  `stores.owner_id` ever gains `ON DELETE SET NULL`.
- **The band is computed from the rows the screen loaded** (`LIMIT 100`, newest
  first). A store with more than 100 historical holds would see counts scoped to
  those — the dashboard's `fetchStoreStats` is the unscoped number and is the one
  to trust for a total.
- **This is a display, not an alarm.** There is no push notification for the T-2h
  store summary; it is an in-app notification row plus the dashboard chip, and
  the countdown only moves while a screen is open (30-second ticker).
