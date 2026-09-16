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
                      grant_pickup_extension()     ────────┤   +24h, ONCE, only while live,
                      (store owner, with a REASON)         │   stock untouched, reminder re-armed,
                                                           │   written to the audit trail
                                                           │
                                                           ├── cancel_pickup_reservation()   [customer
                                                           │   or seller] → cancelled  ✔ stock released
                                                           └── expire_pickup_reservations()  [sweep]
                                                               → expired  ✔ stock released
```

**The hold window is bounded on purpose.** A free hold should survive "I am on
my way but I will not make 6pm" — and it must never become a way to park a
store's stock indefinitely. There are **two independent budgets**, and the
ceiling is their sum:

| Budget | Constant | Who may spend it | What it needs |
|---|---|---|---|
| base window | `pickup_reservation_hold_hours()` = 24 h | — | — |
| the customer's own extension | `pickup_reservation_max_extensions()` = 1 × `pickup_reservation_extension_hours()` = 24 h | the customer | nothing (self-service) |
| the store's goodwill grant | `pickup_reservation_max_store_extensions()` = 1 × `pickup_reservation_store_extension_hours()` = 24 h | the store owner only | a **recorded reason** |

So the customer can reach **48 h on their own**, and a generous store can reach
**72 h total** — `pickup_reservation_max_window_hours()`. Spending one budget
does not touch the other: a customer who has used their extension does not stop
a store from being kind, and a store that has been kind does not consume the
customer's allowance. See §5 for the rules on both paths and the CHECK that
enforces the ceiling.

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
| `reminder_sent_at` | makes the T-2h reminder exactly-once. **Cleared by either extension path**, because the new deadline is owed its own warning |
| `extension_count` | `0..max_extensions` — the customer's own asks. Stored rather than derived so the cap is auditable on the row itself |
| `store_extension_count` | `0..max_store_extensions` — goodwill grants. Separate from `extension_count` by design (see §5), so "the customer asked" and "we chose to give them more time" can never be read as the same thing |

Indexes: `(store_id, status)`, `(customer_id, created_at DESC)`, plus two
partial indexes on `pickup_deadline` scoped to `status = 'active'` —
only `active` rows can ever be picked up by either sweep.

**Two CHECK constraints make the promised patience structural**, so no code path
— present or future — can exceed it:

- `pickup_reservations_within_max_window` — `pickup_deadline <= created_at +
  pickup_reservation_max_window_hours()`, i.e. the **72 h ceiling**, and that
  function is the *sum of every budget* so a new one cannot be added and
  forgotten (`24 × (1 + 1 + 1)`). The functions it calls are `IMMUTABLE`
  constants, which is what makes them usable in a CHECK; if any number is ever
  changed, existing rows are *not* re-validated, so it is a data-affecting change
  rather than a config tweak.
- `pickup_reservations_within_extension_cap` — `extension_count <= max_extensions`
  **and** `store_extension_count <= max_store_extensions`, each against its own
  budget, so neither counter can be pushed past its own ceiling by any path.

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
| `grant_pickup_extension(p_reservation_id, p_reason) → timestamptz` | store owner **only** | gives more time as an explicit goodwill gesture; **requires a reason**, records it in the trail, returns the new deadline. See §5's goodwill rules |
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

### The three extension rules (the customer's own ask)

A hold may be extended only when **all three** hold, and each is enforced in the
RPC (and, for the cap, twice over):

1. **Only the customer — on this RPC.** The store has no way to spend the
   customer's budget on the customer's behalf through this call; a seller
   invoking it gets `FORBIDDEN`. A lenient store uses
   `grant_pickup_extension` below, which is a *different* call with its own
   budget and a mandatory reason. The split is the point: "the customer asked"
   and "we chose to give them more time" must never look alike in the data.
2. **Only before it expires.** Once `pickup_deadline` has passed, the hold may
   lapse at any moment (the sweep has not necessarily run yet), so promising
   more time would promise stock nobody can guarantee. `HOLD_LAPSED`.
3. **Only `max_extensions` times**, each buying one ordinary window,
   `EXTENSION_LIMIT_REACHED` beyond that — and the ceiling is a table CHECK, not
   just this branch. Note that the *customer's* ceiling is what the copy quotes
   (48 h): the store's budget is a favour, and the customer is never told to
   count on it. The refusal says so, and points at the store rather than
   dead-ending.

The `UPDATE` is `FOR UPDATE`, which is what makes the cap concurrency-safe: two
simultaneous taps serialize, and the second sees `extension_count` already
incremented and is refused — the same class of race as the duplicate-hold index.
**Stock is not touched**: the units left `inventory.stock` when the hold was
created, and more time does not change that. Nothing is charged, because a hold
is free and so there is nothing to re-authorize.

### The store's goodwill grant (a second, separate budget)

`grant_pickup_extension(p_reservation_id, p_reason)` lets a store owner be
lenient without touching the customer's allowance, and four rules bound it —
all checked under `FOR UPDATE`, so two simultaneous taps cannot double a grant:

1. **Only the store that owns the hold.** Not another seller, not the customer
   (a customer approving their own favour is not a favour), not an admin acting
   silently. `FORBIDDEN`.
2. **Only while the hold is live.** Past the deadline the units may be released
   at any moment, so adding time would promise stock the sweep is about to take
   back. `HOLD_LAPSED`.
3. **Only `store_extension_hours` (24 h) and only `max_store_extensions` (once)
   per hold.** More than that is not goodwill, it is a bulk reservation with
   extra steps. `STORE_EXTENSION_LIMIT_REACHED`.
4. **Never without a reason**, 3–280 characters after trimming, enforced by the
   RPC *and* by a CHECK on the trail table, so an unexplained grant is
   impossible to insert by any path. `INVALID_REASON`.

The move is recorded in `public.pickup_reservation_extension_grants` **in the
same transaction as the deadline change**, so a grant can never exist without
its record (or the reverse):

| Column | Notes |
|---|---|
| `reservation_id` | → `pickup_reservations`, **cascade** — the trail exists to explain *a hold's* deadline, so it travels with the hold. It is not a compliance archive |
| `customer_id` / `store_id` | denormalised, so "everything this store gave away" and "everything this customer was given" are each a single-table read |
| `granted_by` | → `profiles`, **`ON DELETE SET NULL`** (the convention `gcash_payment_decision_audit.seller_id` already uses): deleting the seller must not delete the record that a favour happened |
| `previous_deadline` / `new_deadline` | the move as a before/after pair, so one row explains a deadline without replaying the sequence |
| `hours_granted` | what the deadline moved by |
| `reason` | **required**, `CHECK (length(btrim(reason)) BETWEEN 3 AND 280)` |

Like the hold table it is **`SELECT`-only** in RLS (customer, store owner,
admin), so the RPC is the only write path and a hand-crafted `INSERT` cannot
fabricate a trail; and it is folded into the **device gate**. The customer's
notification carries the reason verbatim, because an unexplained later deadline
reads like a glitch — and the store's own tile prints it back
(`You gave 24h: "…"`), which is what makes a later deadline on the board
explainable without asking.

**Stock is untouched here too** (the units left `inventory.stock` at creation)
and nothing is charged. The new deadline **re-arms** `reminder_sent_at`, exactly
as the customer path does — a granted deadline is owed the same T-2h warning as
any other.

#### The customer's side of the ledger: the goodwill history

The reason a grant exists is that a *person* was generous, so the record has to
outlive the hold it was granted on. It does: the customer has a **history screen**
(`PickupGoodwillScreen`, reached from *My Pickup Reservations*) listing **every**
grant on their holds, newest first, each row carrying the store, the pair, the
hours, the reason **as the store wrote it**, the deadline move (`from … to …`) and
when it was given. Nothing about that list depends on the holds list: a hold that
was collected, released, or pushed past the holds query's `LIMIT` still has its
grant here, which is the entire point — the per-hold note only exists while its
hold is on screen.

**No migration was needed.** The trail is already readable to the customer
through RLS (one of its three `SELECT` audiences), and the *names* arrive by
embedding the hold: `pickup_reservations(size, products(name, stores(name)))`,
which resolves only because `reservation_id` is a foreign key to
`pickup_reservations`. That embed is therefore load-bearing — a renamed column
renders an empty history rather than failing, and a renamed relation is a `400` on
the whole query — so it is pinned from both ends: a pgTAP assertion that the trail
FKs the hold (assertion 60 of `store_pickup_extensions.test.sql`), and a contract
test reading the embed path out of the service. The seller's trail stays a
**single-table** read: it renders beside holds it already has, and the contract
test pins that exactly one query asks for the embed.

Ten guards around the history were **mutation-tested** (dropping the embed,
naming the wrong relation, reading `size` off the flat row instead of the embedded
hold, counting grants where the header should count stores, sharing one select
between the two audiences, filtering the history down to holds still in the list,
and the link being always-on or never-on). One came back green on the first pass,
and for a reason worth recording: the two halves of the link assertion lived in
**different tests**, so an always-false condition satisfied the negative half on
its own. They are now a matched pair inside one test — the only thing the
mutation pass was able to prove by failing to fail.

Two smaller decisions worth keeping: the action to open the history appears
**only when there is something to read** (same rule as the seller screen's
`Lapsing soon` chip — an action that opens an empty screen is noise), and the
screen says in one line that the customer's **own** extension is *not* listed
there, because the trail is the store's side of the ledger and mixing the two would
make a favour indistinguishable from an entitlement.

### The counter code — how a seller finds the hold in front of them

The customer's card carries a **six-character code** (`4F7-K2Q`) and the seller
has a **Collect by code** action in the app bar. That is the whole reason it
exists: at a counter, neither party wants to scroll a list together to work out
which of the store's holds is the pair being handed over.

| Piece | Where | Why it lives there |
|---|---|---|
| `pickup_code` column + its CHECK | `20260915170000` §3/§3b | nullable, unique across the whole table, shaped by a regex that is a *literal copy* of the alphabet — a CHECK cannot call a function defined in a later migration |
| `pickup_code_alphabet()` / `pickup_code_length()` | `20260916140000` | one definition each, read by the generator, the pgTAP suite and the Dart constants (3 copies, pinned to each other by the contract test) |
| `generate_pickup_code()` | `20260916140000` | loops until free rather than "generate and hope": a collision at INSERT would fail the *customer's* request with a `23505` that has nothing to do with anything they did. Randomness is `gen_random_uuid()` hashed, not `random()` — `random()` is session-seeded, so a burst of inserts in one transaction could draw the same stream |
| `assign_pickup_code()` (BEFORE INSERT trigger) | `20260916140000` | every insert path gets one, including a hand-written repair, and there is exactly one place that decides the format |
| `normalize_pickup_code()` | `20260916140000` | upper-cases and strips separators — and deliberately does **no look-alike substitution** |
| `find_pickup_reservation_by_code(p_code)` | `20260916140000` | the only resolver, scoped by joining `stores.owner_id = auth.uid()` |
| `fulfill_pickup_reservation_by_code(p_code, p_payment_method)` | `20260916140000` | resolve + collect in ONE call, delegating to `fulfill_pickup_reservation` |

**Why the alphabet omits I, L, O, U, 0 and 1.** A code is read off a phone screen
across a counter and often spoken aloud, and those six are the ones that turn into
each other. 30 symbols × 6 characters is ~729M combinations against a table that
holds a few thousand rows, so the exclusions cost nothing.

**The code is not a secret; the store scoping is the security boundary.** Knowing
a code reveals nothing and permits nothing — but *without* the join through
`stores.owner_id`, any seller could enumerate codes and pull up another store's
holds, which is somebody else's business (who is holding what, and when they are
coming to collect it). So another store's code is reported **exactly like a code
that does not exist**, same `NOT_FOUND` text, because a distinguishable error
would let the lookup be used to probe for real codes. A RESOLVED hold still
resolves — a dispute ("this is the pair the customer showed me") is precisely when
a seller needs the trail — and the app then says "already collected" instead of
pretending the code was wrong.

**Delegation, not a second implementation.** `fulfill_pickup_reservation_by_code`
does one lookup and calls `fulfill_pickup_reservation`; the ownership check, the
`ALREADY_RESOLVED` guard, the POS order and the single stock draw all stay in one
place, so a rule added there cannot be forgotten here.

**⚠️ Two assertions here were too weak until they were mutation-tested.** Removing
the store join, the length pre-check, the trigger's assignment, the alphabet's
exclusions, the index's uniqueness and the CHECK's character class each failed a
named assertion — but replacing the delegation with a bare `RETURN v_id` (resolve
the code, collect nothing) **passed** the original `lives_ok`. That is exactly the
shape of a green test proving nothing: the description said "one call with the
code collects the hold" while the assertion only proved the call did not raise.
It now captures the returned id, checks it against `orders`, and checks it is *not*
the hold's own id. The general lesson: `lives_ok` around an RPC is not a test that
the RPC did anything.

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
| The **counter code** on a live hold — `Show this code at the counter`, grouped as `4F7-K2Q`, selectable so it can be copied or texted to whoever is collecting on the customer's behalf. Placed with the countdown because those are the two facts that matter while standing at the till, and neither should need a tap. A hold with no code renders **nothing** rather than a placeholder: a made-up code is worse than no code, because the seller would type it | `lib/screens/customer/my_pickup_reservations_screen.dart` |
| Seller's incoming holds ("customer arrived — fulfill", manual release, per-tile countdown, and an `extended ×N` marker so a later deadline always has an explanation), with the counter code printed on each tile so a seller can eyeball that it matches what the customer says | `lib/screens/seller/pickup_reservations_screen.dart` |
| **Goodwill history** (app-bar action, shown only when a grant exists): every time a store gave one of your holds more time — store, pair, hours, the reason, the deadline move, and when — including grants on holds the list no longer contains | `lib/screens/customer/pickup_goodwill_screen.dart` |
| **Collect by code** (app bar): type the `6`-character code (spaces and dashes are fine, it is normalised) → the hold it resolved is shown with the customer's name and the code → confirm → "how was it paid?" → recorded as a sale. It resolves **before** asking for payment, so a seller is never asked "cash or GCash?" about a hold they have not seen | `lib/screens/seller/pickup_reservations_screen.dart` |
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
device-gated or explicitly exempt") fails the build. 28 tables are gated in a
clean local database — including `pickup_reservation_extension_grants`, which
the store-grant migration folds in for the same reason: it names a customer and
a store. (The sweep is re-runnable, so the *live* count drifts and is
occasionally higher; the pgTAP invariant therefore asserts named tables plus a
floor rather than an exact number — do not "fix" a higher live count.)

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

The base file is **applied live** as of 2026-09-16, but a **revision behind**
(no `store_extension_count`, no summed 72 h ceiling, no `pickup_code`); the
store-grant and counter-code migrations are **not yet applied**. See
`supabase/MIGRATIONS_LIVE_STATUS.md` for the rows and the ordering.

**The deploy order matters, and it is: base file AGAIN → store grant → counter
code.** All three are re-runnable. The base file must go first because both later
files depend on columns/functions it declares, and applying either alone against
the live revision would succeed and then have its first call refused by the
stale CHECK or fail on a missing column. Applied through the SQL Editor:
`CREATE TABLE IF NOT EXISTS` is a no-op on an existing table, so files here must
**converge** their tables (§3b, and the same block in the store-grant file)
rather than merely create them — an inline `CHECK` is created only alongside its
column, so a missing constraint has to be named and re-added explicitly, which
both files now do.

The customer's **goodwill history** needs no migration at all: the trail is
already readable to the customer through its own `SELECT` policy, and the store
and product names come from embedding the hold. It is an app-only change, which is
also why it can ship in any release window.

Both later migrations are **additive**: nothing calls `grant_pickup_extension` or
the by-code RPCs until a build ships the seller action / the customer's band, so
they can be applied without a release in the same window. Apply them *before*
that build, or those actions fail (`NOT_FOUND`). The counter-code migration adds
**no new table**, so it changes nothing about the device-gate count.

The device gate ships with **enforcement OFF**, so gating
`pickup_reservations` changes nothing until that switch is thrown (apply → ship
the build → `select public.set_device_enforcement(true);`).

## 11. Test coverage

| File | Assertions | Covers |
|---|---|---|
| `supabase/tests/store_pickup_extensions.test.sql` | 60 | the store's goodwill grant: the happy path (deadline moves by exactly 24 h, `store_extension_count` 1, the customer's `extension_count` **untouched**, stock untouched, `reminder_sent_at` re-armed); a missing/short/whitespace-only **reason refused** and no row written; a **wrong store**, the customer, and anonymous all `FORBIDDEN`; the **WHEN rules in their own right**, on a third hold so a spent budget cannot be what the failure is about — a hold with a **backdated deadline** is refused `HOLD_LAPSED` and a **cancelled** one `ALREADY_RESOLVED`, neither leaving a trail row; the **second grant** refused by the cap and the counter not double-incremented; a hand-written `UPDATE` past the 72 h ceiling refused by the CHECK (72 h itself accepted); the trail row's contents (who, from which deadline to which, how many hours, why) and its `granted_by` surviving the seller's deletion; both sides notified, the customer's notification carrying the reason; the table being device-gated; and **the FK the customer's history embeds through** (`reservation_id → pickup_reservations(id)`), which is what makes the history query resolvable rather than a `400` |
| `supabase/tests/pickup_reservations.test.sql` | 129 | happy path; **over-cap rejected**; **insufficient stock rejected**; the compare-and-set under a concurrent second request; the partial unique index (a second `active` row is `23505`, a cancelled one does not block); stock held on request and released on cancel **and** on expire **with no double-release when the sweep races a manual cancel**; a past-deadline `active` hold is expired while a live one is untouched; the sweep is idempotent when run twice; fulfil writes the order with `source='pos'` / `paid` / `received`, sets `fulfilled`, **does not double-draw inventory**, and feeds `units_sold`; the T-2h window fires once and never twice; the **store summary** (one per owner per batch, correct counts, singular wording, per-store isolation, silent on a second run, and never addressed to the customer); and the ownerless-store guard, which must not abort the sweep; and the **extension rules**: the window constants, both CHECK constraints, extend moves no stock, a second extension refused, a `created_at + 72 h` UPDATE refused by the constraint itself, only the customer may extend (not another customer, not the store, not anonymous), a lapsed hold refused, and the reminder **re-armed** so the new deadline gets its own T-2h warning |
| `supabase/tests/pickup_codes.test.sql` | 45 | the counter code: the column, its **UNIQUE** index (whole table, so a resolved hold still resolves) and the BEFORE INSERT trigger; the alphabet (30 symbols, none of I/L/O/U/0/1) and the length, **read from the SQL functions and compared to the column CHECK's literal regex**; normalisation — case and separators stripped, **and no look-alike substitution** (`O0I1` stays `O0I1`); 200 generated codes all match the CHECK and none collide; a hand-written code outside the alphabet or of the wrong length is refused, a well-formed one (including `4f7-k2q`, normalised on the way in) is accepted; the owning store resolves its code — as typed, lowercase, or with separators — while **another store, and the customer, get the same `NOT_FOUND`**, and a part-typed code says how long a code is; one call collects the hold **and returns the ORDER's id, not the hold's**; a second collection is refused `ALREADY_RESOLVED` while the code still resolves (the dispute case); the collection is a real POS sale (`pos/paid/received`) with one line item and **no second stock draw**; and another store cannot collect from a code |
| `test/services/pickup_reservation_contract_test.dart` | 38 | the Dart↔SQL contract: the cap constant matches `pickup_reservation_max_quantity()`, **the window constants match their SQL functions** (following `extension_hours → hold_hours` indirection instead of trusting a literal), the ceiling is still a table CHECK **and is the sum of every budget**, both budgets have their own counter CHECK, the RPC names and argument names match the migration, **each extension path is defined in exactly one file** (re-applying one cannot shadow the other), a grant spends the store's counter and never the customer's, every code the grant RPC raises has friendly copy, the reason bound is the same 3–280 on both sides, the columns the model selects are the columns the table declares, the trail is `SELECT`-only + device-gated, and the migration stays separate from `bulk_reservations`. Plus **the counter code**: the Dart alphabet, the SQL function and the column CHECK's literal regex are the same 30 symbols (a drift makes every generated code un-insertable), the code length is read from the SQL function rather than a second literal, the app normalises exactly the way the server does and folds no look-alikes, the seller UI reaches a hold **through the scoped RPC** (the join to `stores.owner_id = auth.uid()` is pinned, so the app is not filtering store scope itself), fulfilment from a code **delegates rather than re-implements**, and the app never generates or stores a code itself |
| `test/services/pickup_reservation_service_test.dart` | 94 | **the goodwill history's query** (the customer's trail asks for its own columns *plus* the embedded hold and its product and store; the embedded names land on the model; a flat row from the seller's select parses with no names instead of throwing; a `null` to-one embed is read as absent; and the summary's counts, distinct stores and empty case); **the counter code** (normalised before the RPC is asked, `resolveCode`'s call shape, the defensive no-id branch raising copy the mapper already explains, `fulfillByCode`'s one-call shape + default method, `normalizeCode` stripping case and separators **but inventing nothing**, the alphabet excluding the ambiguous six, and `pickupCodeLabel` grouping a real code while passing anything else through); error mapping (`ABOVE_PICKUP_CAP`, `RESERVATION_ALREADY_EXISTS`, the concurrent `23505` loser, `EXTENSION_LIMIT_REACHED` — **and that the store's cap is matched before it, since `STORE_EXTENSION_LIMIT_REACHED` contains it** — `INVALID_REASON`, `HOLD_LAPSED`, `INSUFFICIENT_STOCK`, `FORBIDDEN`, …), countdown formatting, the edge case that a row with no deadline must not read as "Expired", `fetchStoreStats`'s single-query shape, the whole `PickupHoldSummary` matrix (the 2-hour boundary inclusive, lapsed ≠ lapsing, resolved holds ignored, a missing quantity read as one pair, pluralisation, and the two entry points agreeing), **the extension rules** (cap spent, lapsed refused even with the cap unused, resolved and deadline-less holds refused, an unknown `extension_count` read as none used, and `extend()`'s call shape plus a reply with no parseable deadline), and **the store's goodwill grant** (its own constants and the summed ceiling, the two budgets being independent in both directions, a lapsed/resolved/deadline-less hold never offered, the note distinguishing a grant from the customer's own ask, `grantExtension()`'s call shape, that it is a *different RPC* from `extend()`, the trail queries scoped to the right audience and ordered newest-first, and the deadline formatter) |
| `test/widgets/pickup_goodwill_test.dart` | 7 | the history screen: a gift reads as a store, the pair, the time `+24h` **and the reason quoted**; the header counts exactly what the list below shows (and one gift is not written in the plural); a grant whose embed brought back no names still shows its reason, with no dangling `· size` row; a grant with no timestamps skips the move line rather than rendering `null`; the screen states that the customer's own extensions are not in this list; and an empty history explains itself |
| `test/widgets/pickup_reservation_sheet_test.dart` | 10 | the sheet: free/no-deposit copy, the size pre-selected on the detail screen, a single in-stock size needing no tap, the stepper never exceeding the cap or the live stock, larger orders pointed at bulk, and **submit inert until a size is chosen** |
| `test/widgets/seller_pickup_reservations_test.dart` | 20 | **the counter flow** (the code printed on the tile, the action taking a typed lower-case dashed code and normalising it before the lookup, confirming against the pair in hand before payment, backing out recording nothing, the sale going through the **by-code RPC alone** — never the id path as well, which would be two sales for one pair — a code matching nothing reading as *no match* rather than a deleted hold, and an already-collected hold saying so instead of reading as a bad code); the store's band and filter: the counts, nothing rendered when nothing is lapsing, a lapsed hold counted as coming back, the chip and the band's *Show* both narrowing to the urgent holds, and resolved holds neither counted nor offered. Plus **the goodwill grant**: the labelled action on a live hold, the dialog naming the hold it is about, an empty reason refused *in the dialog* (so the server is never asked), a preset chip filling an editable field and being sent verbatim, a server refusal shown as copy, the action **withdrawn** once the store's budget is spent and on a lapsed hold, and the recorded reason printed back on the tile (never a grant belonging to another hold) |
| `test/widgets/my_pickup_reservations_test.dart` | 14 | **the goodwill history link** (offered only when a grant exists — both halves asserted in one test, since an always-false condition would satisfy the negative on its own — and a grant on a hold the list **no longer contains** still reaches the screen with its reason, which is the feature's whole justification); **the counter code** on the card (visible without a tap, grouped as `4F7-K2Q`, and nothing rendered for a hold with no code — a placeholder would be typed by the seller); the customer's extension action: offered on a live hold with the amount of time named, withdrawn once extended and once lapsed, the dialog naming the store's side, confirming calls the RPC and reports the new deadline, backing out asks for nothing, a refusal reads as copy, and a resolved hold offers neither action. (A lapsed hold still carries the `Extend 24h` *label*, which is what gives this file teeth against the screen dropping its own gate.) Plus **the store's grant**: shown with its reason and in step with the hold's own note, never a grant belonging to another hold, and a **failed trail fetch costing the explanation but not the holds** (the graceful-degradation promise the release notes make) |

Verified: **940** Flutter tests pass, `flutter analyze` clean, and **11 files /
491 DB assertions PASS from a clean `supabase db reset`** (129 + 60 + 45 for
these three pickup files). Every rule in the counter-code migration was
**mutation-tested** (eight SQL mutations + eight Dart ones, each expected to fail
a named assertion). One mutation stayed green on the first pass — a by-code
fulfil that resolved the code and collected nothing, which the original
`lives_ok` could not tell apart from the real thing. That is why assertion 37 now
checks the *returned* id against `orders`; see the counter-code section in §5.

## 12. Known limitations

- **An extension cannot be undone, and a lapsed hold cannot be extended.** Once
  the deadline has passed the only routes are collection (the seller can still
  fulfil it, briefly) or a fresh reservation. The asymmetry is deliberate: the
  server cannot promise stock it may be about to release.
- **Raising the two window constants later does not retro-validate rows.** The
  CHECKs are evaluated on write, so changing `pickup_reservation_hold_hours()`
  or `pickup_reservation_max_extensions()` is a data-affecting change.
- **A store's grant is once per hold, and cannot be undone.** The store's budget
  (`pickup_reservation_max_store_extensions()`) is per *hold*, not per customer
  or per day, so a lenient store that re-holds the same pair for the same
  customer can grant again on the new hold. There is no way to revoke a grant —
  shortening a deadline is not something a customer could be expected to
  discover — and no way to grant after the deadline has passed (`HOLD_LAPSED`),
  because the units may already be back on the shelf. Raising either budget is a
  data-affecting change (§3).

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
