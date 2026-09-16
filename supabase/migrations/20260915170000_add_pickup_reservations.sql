-- ══════════════════════════════════════════════════════════════════════
-- Pickup reservations — the small, FREE, no-deposit hold (ANQUI item 14)
-- ══════════════════════════════════════════════════════════════════════
-- "Reserve for pick up (expires after 24 hours)". CLIENT DECISION: a small
-- (1–2 pair) customer pickup hold requires NO deposit — the stock is simply
-- released if it is not collected in 24 hours.
--
-- ⚠️ THIS IS A DIFFERENT SYSTEM FROM `bulk_reservations`. Read this before
--    touching either one:
--
--   bulk_reservations            pickup_reservations (this file)
--   ─────────────────────────    ────────────────────────────────
--   reseller scale (50 pairs)    1–2 pairs, walk-in customer
--   seller approves first         instant, no approval
--   status machine w/ pending,    one state: `active` until it resolves
--     awaiting_deposit, approved
--   20% non-refundable deposit    FREE — no money, no deposit table
--   deadline chosen by seller     24 h; +24 h once by the customer, and +24 h
--                                 more by the store as an audited goodwill
--                                 grant (≤ 72 h — see §2b)
--   hold against TOTAL stock      hold against ONE size
--
-- They share exactly TWO things and nothing else: `inventory.stock` as the
-- place a hold physically lives (units are moved OUT of it), and the
-- `reservations` notification category. Nothing here reads, writes or
-- depends on `bulk_reservations` / `bulk_reservation_deposits` — a deposit
-- or an approval step appearing in this flow is a bug.
--
-- THE HOLD MECHANISM (identical to the bulk system's, deliberately):
-- requesting decrements `inventory.stock` for the reserved size with a
-- `stock >= quantity` compare-and-set; cancel/expire/fulfill-handover never
-- double-draws. This is the SAME mechanism the bulk flow uses, not a second
-- parallel concept — and it is the only mechanism the app actually reads
-- for availability (size pickers filter on `stock > 0`, and
-- `checkout_cart_summary` resolves a size by requiring `stock > 0`), so a
-- size held to 0 is genuinely unbuyable by everyone else.
--
-- THE ONE INVARIANT TO NOT BREAK: **the hold IS the draw.** At fulfill the
-- order is written but inventory is NOT touched again — the units left
-- `inventory.stock` when the hold was created, so decrementing again would
-- double-draw them. (Verified while writing this: `order_items` has NO
-- triggers in this schema, so nothing decrements on order insert; see §
-- "VERIFICATION" at the bottom. If a decrement trigger is ever attached to
-- `order_items`, `fulfill_pickup_reservation` must change to
-- release-then-draw, and the pgTAP suite asserts the current behaviour so
-- that change cannot happen silently.)
-- ══════════════════════════════════════════════════════════════════════

-- 1. STATUS ENUM ──────────────────────────────────────────────────────
-- Four states, not the bulk flow's eight: there is no approval and no
-- deposit, so there is nothing to wait for.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pickup_reservation_status') THEN
    CREATE TYPE pickup_reservation_status AS ENUM (
      'active',     -- holding stock until pickup_deadline
      'fulfilled',  -- collected; converted into a POS order
      'cancelled',  -- released early by the customer or the seller
      'expired'     -- the 24h deadline passed; the sweep released it
    );
  END IF;
END
$$;

-- 2. THE CAP ──────────────────────────────────────────────────────────
-- The checklist's own framing is "1–2 pairs". Exposed as a function so the
-- RPC, the pgTAP suite, the docs and the Dart constant
-- (`PickupReservation.maxQuantity`, guarded by
-- `test/services/pickup_reservation_contract_test.dart`) all read ONE
-- number instead of four copies of "2".
CREATE OR REPLACE FUNCTION public.pickup_reservation_max_quantity()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 2; $$;

COMMENT ON FUNCTION public.pickup_reservation_max_quantity() IS
  'Maximum units a single free pickup hold may take. Above this, the customer is pointed at the deposit-gated bulk reservation flow.';

-- 2b. THE HOLD WINDOW AND THE EXTENSION CAP ───────────────────────────
-- MORE time can be granted before a hold lapses (see
-- `extend_pickup_reservation`), because "I am on my way but I will not make 6pm"
-- is a real thing a free hold should survive. What nobody may do is keep a
-- store's stock parked indefinitely, so every way the deadline can move is an
-- explicit, separately-counted budget:
--
--   hold hours          one base window (24h)
--   customer budget     how many times the CUSTOMER may push it (1 × 24h)
--   store budget        how many times the STORE may push it as a goodwill
--                       grant (1 × 24h) — the RPC ships in
--                       20260916120000_add_store_pickup_extensions.sql, which
--                       also records each grant and its reason
--
-- ⇒ three budgets, three numbers, and ONE ceiling that is their sum: 72 hours.
-- It is not merely a rule inside an RPC — it is a table CHECK (see §3) built
-- from `pickup_reservation_max_window_hours()`, so even a hand-written
-- INSERT/UPDATE cannot exceed it, and widening one budget cannot forget the
-- bound.
--
-- The two sides are deliberately NOT the same act. The customer's extension is
-- self-service; the store's is a recorded favour with a reason attached. See the
-- header of the store-grant migration for why that distinction is kept.
CREATE OR REPLACE FUNCTION public.pickup_reservation_hold_hours()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 24; $$;

COMMENT ON FUNCTION public.pickup_reservation_hold_hours() IS
  'Base length of a free pickup hold, in hours. Mirrored by PickupReservation.holdHours in Dart (pinned by test/services/pickup_reservation_contract_test.dart).';

CREATE OR REPLACE FUNCTION public.pickup_reservation_max_extensions()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 1; $$;

COMMENT ON FUNCTION public.pickup_reservation_max_extensions() IS
  'How many times a customer may extend a live hold. Each extension adds pickup_reservation_hold_hours(), so the cap is what bounds how long a store can be made to wait — mirrored by PickupReservation.maxExtensions in Dart.';

CREATE OR REPLACE FUNCTION public.pickup_reservation_extension_hours()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT public.pickup_reservation_hold_hours(); $$;

COMMENT ON FUNCTION public.pickup_reservation_extension_hours() IS
  'Hours added by one extension. Same length as the base hold: an extension buys a customer one more ordinary window rather than an arbitrary amount of time.';

-- The STORE's budget. Defined here, beside the other two, because it is part of
-- what a hold IS — the row's own CHECK bounds itself with it (§3). The RPC that
-- spends it lives in 20260916120000: a store granting time is an explicit,
-- audited favour rather than self-service, so it gets its own file and its own
-- trail instead of being folded into `extend_pickup_reservation`.
CREATE OR REPLACE FUNCTION public.pickup_reservation_max_store_extensions()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 1; $$;

COMMENT ON FUNCTION public.pickup_reservation_max_store_extensions() IS
  'How many goodwill extensions the STORE may grant on one hold (mirrored by PickupReservation.maxStoreExtensions in Dart). Separate from the customer''s own budget so a lenient store is not blocked once the customer has used theirs.';

CREATE OR REPLACE FUNCTION public.pickup_reservation_store_extension_hours()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$ SELECT public.pickup_reservation_hold_hours(); $$;

COMMENT ON FUNCTION public.pickup_reservation_store_extension_hours() IS
  'Hours added by one store goodwill grant. One ordinary window, exactly like the customer''s extension — a grant is patience, not an arbitrary new deadline.';

-- THE CEILING, as one expression. Every budget above is summed here so the
-- table CHECK cannot be widened for one side and forgotten for the other, and so
-- the answer to "how long can this store''s stock be held?" is a single call.
CREATE OR REPLACE FUNCTION public.pickup_reservation_max_window_hours()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT public.pickup_reservation_hold_hours()
           * (1 + public.pickup_reservation_max_extensions()
                + public.pickup_reservation_max_store_extensions());
$$;

COMMENT ON FUNCTION public.pickup_reservation_max_window_hours() IS
  'Absolute ceiling on a hold: the base window plus EVERY extension budget (24 × 3 = 72 h). Used by the pickup_reservations_within_max_window CHECK, so no code path — present or future — can exceed it.';

-- 3. TABLE ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pickup_reservations (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id          UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    product_id        UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    -- Size-specific, unlike a bulk hold: the customer wants ONE pair in
    -- ONE size, and `inventory` / `order_items` are both keyed by
    -- (product_id, size), so this matches how stock and sales are keyed
    -- everywhere else.
    size              TEXT NOT NULL,
    quantity          INTEGER NOT NULL CHECK (quantity > 0),
    -- Units physically taken out of `inventory.stock` when the hold was
    -- created. Positive on every `active` row (there is no "pending"
    -- state here — a row exists only because stock was held).
    reserved_stock    INTEGER NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0),
    status            pickup_reservation_status NOT NULL DEFAULT 'active',
    pickup_deadline   TIMESTAMPTZ NOT NULL,
    -- Exactly-once audit stamps.
    reserved_at       TIMESTAMPTZ,
    released_at       TIMESTAMPTZ,
    fulfilled_at      TIMESTAMPTZ,
    -- The POS order this hold became (fulfill). SET NULL rather than
    -- CASCADE: deleting the order must not delete the reservation's
    -- history.
    fulfilled_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    -- Makes the T-2h reminder exactly-once (the reminder sweep only picks
    -- rows where this is still NULL).
    --
    -- CLEARED by `extend_pickup_reservation`: an extended hold has a NEW
    -- deadline, so it is owed a fresh reminder for it. Leaving the stamp set
    -- would silently skip the only warning the customer gets.
    reminder_sent_at  TIMESTAMPTZ,
    -- How many times this hold has been extended (0..max_extensions). Stored
    -- rather than derived so the cap is auditable on the row itself.
    extension_count   INTEGER NOT NULL DEFAULT 0 CHECK (extension_count >= 0),
    -- Goodwill extensions the STORE has granted (0..max_store_extensions),
    -- counted separately from the customer's own budget on purpose: a store
    -- being generous must not consume the customer's allowance, and vice versa.
    -- The reason for each one lives in pickup_reservation_extension_grants.
    store_extension_count INTEGER NOT NULL DEFAULT 0 CHECK (store_extension_count >= 0),
    -- The code the customer reads out at the counter and the seller types in to
    -- find this exact hold (20260916140000 owns the generator, the lookup and
    -- the one-action fulfil). Six characters from
    -- `pickup_code_alphabet()` — no I, L, O, U, 0 or 1, because a code is spoken
    -- aloud and copied off a phone screen, and those six are exactly the ones
    -- that get misread as 1 I, 0 O, VV, etc.
    --
    -- NULLABLE, and not merely for legacy rows: the alphabet and the length are
    -- asserted to match this regex by the contract test, so the CHECK *is* the
    -- shape rule and a hand-written code cannot be a short one. A code is
    -- assigned by a BEFORE INSERT trigger, so every insert path gets one.
    pickup_code       TEXT CHECK (pickup_code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$'),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3b. CONVERGE THE TABLE (do not merely create it) ───────────────────
-- `CREATE TABLE IF NOT EXISTS` above is a NO-OP when the table already exists —
-- it does not reconcile an existing table with the definition above. That makes
-- "idempotent, safe to re-run" weaker than it sounds for a file that is applied
-- BY HAND through the SQL Editor (see supabase/MIGRATIONS_LIVE_STATUS.md): it is
-- safe on a database where THIS revision already ran, but NOT on one holding a
-- table created by an EARLIER REVISION OF THIS SAME FILE.
--
-- That is not hypothetical. An earlier hand-apply of the pre-extension version of
-- this migration left a `pickup_reservations` with no `extension_count`; the
-- CREATE TABLE above silently kept the old shape and the
-- `pickup_reservations_within_extension_cap` constraint below then failed with:
--
--     ERROR: 42703: column "extension_count" does not exist
--
-- — an error naming a statement whose own text looks correct, which is exactly
-- why it is worth this block. Every column is listed (not only the ones added
-- after the first release) so the table converges from ANY earlier shape, and so
-- this block doubles as the one place to read what a hold actually stores.
--
-- IF NOT EXISTS matches on NAME only: this reconciles MISSING columns, not
-- CHANGED ones. A column that already exists with a different type or default is
-- left alone, and (as with the CHECKs below) existing rows are not re-validated.
ALTER TABLE public.pickup_reservations
    ADD COLUMN IF NOT EXISTS id                 UUID DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS customer_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS store_id           UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS product_id         UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS size               TEXT NOT NULL,
    ADD COLUMN IF NOT EXISTS quantity           INTEGER NOT NULL CHECK (quantity > 0),
    ADD COLUMN IF NOT EXISTS reserved_stock     INTEGER NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0),
    ADD COLUMN IF NOT EXISTS status             pickup_reservation_status NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS pickup_deadline    TIMESTAMPTZ NOT NULL,
    ADD COLUMN IF NOT EXISTS reserved_at        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS released_at        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS fulfilled_at       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS fulfilled_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reminder_sent_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS extension_count    INTEGER NOT NULL DEFAULT 0 CHECK (extension_count >= 0),
    ADD COLUMN IF NOT EXISTS store_extension_count INTEGER NOT NULL DEFAULT 0 CHECK (store_extension_count >= 0),
    ADD COLUMN IF NOT EXISTS pickup_code        TEXT CHECK (pickup_code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$'),
    ADD COLUMN IF NOT EXISTS created_at         TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now());

-- …and the column CHECKs that arrived with those columns. An inline CHECK is
-- created only WITH its column, so `ADD COLUMN IF NOT EXISTS` above is a NO-OP
-- on a table that already has the column — a missing CHECK would stay missing,
-- the same gap the header of this block is about. Listed explicitly (DROP + ADD,
-- addressed by the name Postgres gave them) so re-running this file converges the
-- CONSTRAINTS as well as the columns. These four are the ones the hold logic
-- reads: a negative counter would silently corrupt the caps below, and a
-- negative `reserved_stock` would make a release INCREASE stock it never held.
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_quantity_check;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_quantity_check CHECK (quantity > 0);
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_reserved_stock_check;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_reserved_stock_check CHECK (reserved_stock >= 0);
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_extension_count_check;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_extension_count_check CHECK (extension_count >= 0);
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_store_extension_count_check;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_store_extension_count_check CHECK (store_extension_count >= 0);
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_pickup_code_check;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_pickup_code_check
    CHECK (pickup_code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$');

-- ⚠️ THE HONESTY BOUND, AS A CONSTRAINT.
-- A hold can never keep stock longer than the base window plus every allowed
-- extension. Enforced here rather than only in the RPC (and not only in the
-- app), so the answer to "how long can a customer park this store's stock?" is
-- readable from the schema and cannot be exceeded by any path — including a
-- future RPC that forgets to check.
--
-- The two functions are IMMUTABLE constants, which is what makes them usable in
-- a CHECK. If either is ever changed, existing rows are NOT re-validated — so
-- changing a number here is a data-affecting change, not just a config tweak.
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_within_max_window;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_within_max_window CHECK (
        pickup_deadline <= created_at
            + public.pickup_reservation_max_window_hours() * interval '1 hour'
    );
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_within_extension_cap;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_within_extension_cap CHECK (
        extension_count <= public.pickup_reservation_max_extensions()
    );
-- …and the store's budget is bound the same way, so a hand-written UPDATE
-- cannot hand out unlimited goodwill either.
ALTER TABLE public.pickup_reservations
    DROP CONSTRAINT IF EXISTS pickup_reservations_within_store_extension_cap;
ALTER TABLE public.pickup_reservations
    ADD CONSTRAINT pickup_reservations_within_store_extension_cap CHECK (
        store_extension_count <= public.pickup_reservation_max_store_extensions()
    );

CREATE INDEX IF NOT EXISTS idx_pickup_reservations_store_status
    ON public.pickup_reservations (store_id, status);
CREATE INDEX IF NOT EXISTS idx_pickup_reservations_customer
    ON public.pickup_reservations (customer_id, created_at DESC);
-- The two sweeps' indexes: only `active` rows can ever be picked up.
CREATE INDEX IF NOT EXISTS idx_pickup_reservations_expiry
    ON public.pickup_reservations (pickup_deadline) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_pickup_reservations_reminder
    ON public.pickup_reservations (pickup_deadline)
    WHERE status = 'active' AND reminder_sent_at IS NULL;

-- ONE LIVE HOLD per customer per product+size — enforced by the DATABASE, not
-- only by the RPC's own check.
--
-- WHY BOTH: `request_pickup_reservation` raises a friendly
-- `RESERVATION_ALREADY_EXISTS`, but that check is SERIAL — two simultaneous
-- submits for the same pair both see "no active hold" and both insert, so one
-- customer ends up with two holds on the same pair. (The stock
-- compare-and-set still stops them overselling, so this is not an inventory
-- bug — which is exactly why it would have gone unnoticed.) The partial index
-- is the concurrency backstop: the loser's INSERT raises 23505 and the whole
-- RPC statement rolls back, stock included, because it is ONE statement from
-- the client's point of view. The Dart service maps 23505 to the same
-- "you already have an active hold" copy the RPC's own error produces.
--
-- Partial on `status = 'active'` so a resolved hold never blocks a new one.
-- Exact on `size` (the RPC's own check is deliberately fuzzy — "41" vs "US
-- 41" — and handles the sequential near-duplicate case).
CREATE UNIQUE INDEX IF NOT EXISTS
    idx_pickup_reservations_one_active_per_customer_product_size
    ON public.pickup_reservations (customer_id, product_id, size)
    WHERE status = 'active';

-- The code the counter looks a hold up by (20260916140000 owns the generator,
-- the lookup and the one-action fulfil). UNIQUE over the WHOLE table rather than
-- only the live holds: a resolved hold's code must still resolve for the seller
-- in a dispute ("this is the pair the customer showed me"). Postgres treats
-- NULLs as distinct, so every code-less legacy row coexists happily.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pickup_reservations_pickup_code
    ON public.pickup_reservations (pickup_code);

COMMENT ON TABLE public.pickup_reservations IS
  'Small FREE pickup holds (ANQUI item 14): 1-2 units of ONE size of ONE product, held out of inventory.stock for 24 hours, no deposit and no approval. A separate system from bulk_reservations (deposit-gated reseller holds) — see the header of 20260915170000_add_pickup_reservations.sql.';
COMMENT ON COLUMN public.pickup_reservations.reserved_stock IS
  'Units moved out of inventory.stock for this hold. At fulfill the hold BECOMES the sale, so inventory is not touched again (decrementing twice would double-draw).';
COMMENT ON COLUMN public.pickup_reservations.reminder_sent_at IS
  'Stamped by send_pickup_reservation_reminders() so the T-2h reminder fires exactly once per hold.';

-- 4. RLS ──────────────────────────────────────────────────────────────
-- SELECT only, for the three audiences. Deliberately NO INSERT/UPDATE/
-- DELETE policy: unlike the legacy bulk table, every row here represents
-- stock that has already been taken, so a client-side INSERT could mint a
-- hold-shaped row that holds nothing. `request_pickup_reservation` is the
-- only write path (SECURITY DEFINER below), which also means the cap and
-- the stock check cannot be bypassed by a hand-crafted request.
ALTER TABLE public.pickup_reservations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their own pickup reservations"
    ON public.pickup_reservations;
CREATE POLICY "Customers can view their own pickup reservations"
    ON public.pickup_reservations FOR SELECT
    USING (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Sellers can view pickup reservations for their store"
    ON public.pickup_reservations;
CREATE POLICY "Sellers can view pickup reservations for their store"
    ON public.pickup_reservations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Admins can view all pickup reservations"
    ON public.pickup_reservations;
CREATE POLICY "Admins can view all pickup reservations"
    ON public.pickup_reservations FOR SELECT
    USING (public.is_admin());

-- 5. READ HELPER ──────────────────────────────────────────────────────
-- Units currently held by pickup holds for a product (optionally per size).
--
-- NOTE the deliberate distinction from `reserved_stock_for_product()`: that
-- one reports BULK holds, this one reports PICKUP holds, and **both are
-- already reflected in `inventory.stock`** — neither should be subtracted
-- from it. They exist to explain where stock went, not as a second
-- availability number (subtracting either would double-count the hold).
CREATE OR REPLACE FUNCTION public.pickup_reserved_stock_for_product(
    p_product_id UUID,
    p_size TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(SUM(reserved_stock), 0)
    FROM public.pickup_reservations
    WHERE product_id = p_product_id
      AND status = 'active'
      AND (
        p_size IS NULL
        OR regexp_replace(size, '\D', '', 'g')
           = regexp_replace(p_size, '\D', '', 'g')
      );
$$;

COMMENT ON FUNCTION public.pickup_reserved_stock_for_product(UUID, TEXT) IS
  'Units held by active pickup reservations (all sizes, or one). Already deducted from inventory.stock — do not subtract it again.';

-- 6. RELEASE CORE (shared, exactly-once) ──────────────────────────────
-- Returns a hold's units to `inventory.stock` and flips the status IN THE
-- SAME transaction, guarded on the expected starting status while holding
-- the row lock. That guard is what makes the sweep-vs-cancel race safe:
-- whoever gets there second sees a status that no longer matches and
-- returns without touching stock.
CREATE OR REPLACE FUNCTION public._release_pickup_reservation_stock(
    p_reservation_id UUID,
    p_expected_status pickup_reservation_status,
    p_new_status pickup_reservation_status
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.pickup_reservations%ROWTYPE;
BEGIN
    SELECT * INTO v_reservation FROM public.pickup_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                       -- serialize against cancel/fulfill/sweep

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.status <> p_expected_status THEN
        RETURN FALSE;                 -- already resolved elsewhere: no-op
    END IF;

    IF v_reservation.reserved_stock > 0 THEN
        -- Return the units to the size they came from. If that inventory
        -- row was deleted while the hold was live, recreate it as a
        -- 'Restock' row so the units are never lost (same guard as the
        -- bulk release core).
        UPDATE public.inventory
        SET stock = stock + v_reservation.reserved_stock,
            updated_at = timezone('utc'::text, now())
        WHERE product_id = v_reservation.product_id
          AND size = v_reservation.size;

        IF NOT FOUND THEN
            INSERT INTO public.inventory (product_id, size, stock)
            VALUES (v_reservation.product_id, v_reservation.size,
                    v_reservation.reserved_stock)
            ON CONFLICT (product_id, size)
            DO UPDATE SET stock = public.inventory.stock + EXCLUDED.stock,
                          updated_at = timezone('utc'::text, now());
        END IF;
    END IF;

    UPDATE public.pickup_reservations
    SET status = p_new_status,
        released_at = CASE
            WHEN p_new_status IN ('cancelled', 'expired')
            THEN timezone('utc'::text, now())
            ELSE released_at END,
        fulfilled_at = CASE
            WHEN p_new_status = 'fulfilled'
            THEN timezone('utc'::text, now())
            ELSE fulfilled_at END
    WHERE id = p_reservation_id;

    RETURN TRUE;
END;
$$;

-- 7. REQUEST (customer) ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_pickup_reservation(
    p_product_id UUID,
    p_size TEXT,
    p_quantity INTEGER DEFAULT 1
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer  UUID := auth.uid();
    v_product   public.products%ROWTYPE;
    v_cap       INTEGER := public.pickup_reservation_max_quantity();
    v_size      TEXT := btrim(COALESCE(p_size, ''));
    v_resolved  TEXT;
    v_stock     INTEGER;
    v_deadline  TIMESTAMPTZ;
    v_id        UUID;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    IF p_quantity IS NULL OR p_quantity < 1 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY';
    END IF;
    -- Above the cap the answer is not "no" but "use the other flow": a
    -- distinct code so the app can point at the bulk request sheet.
    IF p_quantity > v_cap THEN
        RAISE EXCEPTION 'ABOVE_PICKUP_CAP (%) — for % or more units request a bulk reservation instead',
            v_cap, v_cap + 1;
    END IF;

    SELECT * INTO v_product FROM public.products
    WHERE id = p_product_id AND is_active = true AND is_published = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;

    IF v_size = '' THEN
        RAISE EXCEPTION 'SIZE_REQUIRED';
    END IF;

    -- Resolve the customer-facing size string against a row that actually
    -- has stock, normalizing non-digits exactly like `checkout_cart_summary`
    -- and `resolveInventorySize` do (so "EU 40" and "40" are one size).
    SELECT size, stock INTO v_resolved, v_stock
    FROM public.inventory
    WHERE product_id = p_product_id
      AND stock > 0
      AND regexp_replace(size, '\D', '', 'g')
        = regexp_replace(v_size, '\D', '', 'g')
    ORDER BY stock DESC
    LIMIT 1;

    IF v_resolved IS NULL THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK (0 available in size %)', v_size;
    END IF;
    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK (%) < %', v_stock, p_quantity;
    END IF;

    -- One live hold per customer per product+size, so one customer cannot
    -- sweep a size off the shelf. Mirrors the bulk flow's rule; repeats are
    -- allowed once the previous hold resolves.
    IF EXISTS (
        SELECT 1 FROM public.pickup_reservations
        WHERE customer_id = v_customer
          AND product_id = p_product_id
          AND status = 'active'
          AND regexp_replace(size, '\D', '', 'g')
            = regexp_replace(v_resolved, '\D', '', 'g')
    ) THEN
        RAISE EXCEPTION 'RESERVATION_ALREADY_EXISTS';
    END IF;

    -- The base window comes from the constant, so "how long is a hold" has one
    -- answer (and the CHECK constraint above uses the same one).
    v_deadline := timezone('utc'::text, now())
                  + public.pickup_reservation_hold_hours() * interval '1 hour';

    -- ── THE HOLD ─────────────────────────────────────────────────────
    -- Compare-and-set: the `stock >= p_quantity` predicate is inside the
    -- UPDATE, so two concurrent requests for the last pair cannot both
    -- succeed (one matches 0 rows and aborts). A failure here raises, and
    -- the raise rolls back the row inserted below — so there is never a
    -- reservation without its stock, or stock without its reservation.
    UPDATE public.inventory
    SET stock = stock - p_quantity,
        updated_at = timezone('utc'::text, now())
    WHERE product_id = p_product_id
      AND size = v_resolved
      AND stock >= p_quantity;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK (0) < %', p_quantity;
    END IF;

    INSERT INTO public.pickup_reservations (
        customer_id, store_id, product_id, size, quantity,
        reserved_stock, status, pickup_deadline, reserved_at
    ) VALUES (
        v_customer, v_product.store_id, p_product_id, v_resolved, p_quantity,
        p_quantity, 'active', v_deadline, timezone('utc'::text, now())
    ) RETURNING id INTO v_id;

    -- Customer confirmation (deadline + what to bring).
    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_customer, 'reservations',
        'Pickup reservation confirmed',
        'We are holding ' || p_quantity || ' × ' || v_product.name ||
        ' (size ' || v_resolved || ') for you until ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC.'
    );

    -- Seller heads-up: stock is off the shelf.
    INSERT INTO public.notifications (user_id, category, title, message)
    SELECT s.owner_id, 'reservations',
           'New pickup reservation',
           'A customer is holding ' || p_quantity || ' × ' || v_product.name ||
           ' (size ' || v_resolved || ') for pickup until ' ||
           to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC.'
    -- `owner_id IS NOT NULL` everywhere a store is notified: the column is
    -- nullable, `notifications.user_id` is NOT NULL, and an ownerless store
    -- would abort whatever RPC happened to touch it.
    FROM public.stores s
    WHERE s.id = v_product.store_id AND s.owner_id IS NOT NULL;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_pickup_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pickup_reservation TO authenticated;

-- 7b. EXTEND (customer, only while the hold is still live) ─────────────
-- A free hold should survive "I am on my way but I will not make 6pm". What it
-- must NOT become is a way to park a store's stock indefinitely, so three rules
-- bound it:
--
--   1. ONLY THE CUSTOMER — here. A store CAN add time, but not through this
--      RPC: it has its own explicit, reason-carrying, audited path
--      (`grant_pickup_extension`, 20260916120000_add_store_pickup_extensions.sql)
--      with its own budget, so a favour is recorded rather than silent. This
--      function stays customer-only — it is the self-service door.
--   2. ONLY BEFORE IT EXPIRES. Once `pickup_deadline` has passed the hold may
--      lapse at any moment (the opportunistic sweep just has not run yet), so
--      promising more time would be promising stock nobody can guarantee.
--   3. ONLY max_extensions TIMES, and each buys one ordinary window. The total
--      is therefore ≤ 48h from reservation, and that ceiling is ALSO a table
--      CHECK (`pickup_reservations_within_max_window`) so no code path — present
--      or future — can exceed it.
--
-- Stock is untouched: the units left `inventory.stock` when the hold was
-- created and more time does not change that. Nothing is charged (a hold is
-- free, so there is nothing to re-authorize).
--
-- Returns the NEW deadline so the app can show it without a refetch.
--
-- `FOR UPDATE` is what makes the cap concurrency-safe: two simultaneous taps
-- serialize, and the second sees `extension_count` already incremented and is
-- refused — the same class of race as the duplicate-hold index.
CREATE OR REPLACE FUNCTION public.extend_pickup_reservation(
    p_reservation_id UUID
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer  UUID := auth.uid();
    v_row       public.pickup_reservations%ROWTYPE;
    v_max       INTEGER := public.pickup_reservation_max_extensions();
    v_added     INTEGER := public.pickup_reservation_extension_hours();
    v_deadline  TIMESTAMPTZ;
    v_left      INTEGER;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_row FROM public.pickup_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    -- Customers see their own rows through RLS, so FORBIDDEN here means a
    -- hand-crafted call naming someone else's hold.
    IF v_row.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    IF v_row.status <> 'active' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    IF v_row.pickup_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'HOLD_LAPSED — this hold has already run out; reserve again';
    END IF;

    IF v_row.extension_count >= v_max THEN
        RAISE EXCEPTION 'EXTENSION_LIMIT_REACHED (%) — this hold has already been extended; reserve again after it lapses',
            v_max;
    END IF;

    v_deadline := v_row.pickup_deadline + v_added * interval '1 hour';
    v_left     := v_max - (v_row.extension_count + 1);

    UPDATE public.pickup_reservations
    SET pickup_deadline  = v_deadline,
        extension_count  = extension_count + 1,
        -- The OLD deadline's reminder does not apply to the NEW one. Clearing
        -- it re-arms the T-2h warning; leaving it set would silently mean the
        -- customer is never told the second deadline is close.
        reminder_sent_at = NULL
    WHERE id = v_row.id;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_customer, 'reservations',
        'Pickup hold extended',
        'Your hold on ' || v_row.quantity || ' × size ' || v_row.size ||
        ' now runs until ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') ||
        ' UTC.' || CASE WHEN v_left = 0
                        THEN ' That was your last extension.'
                        ELSE ' You can extend ' || v_left || ' more.'
                   END
    );

    -- The store's commitment just grew, so it is told rather than left to
    -- notice a later deadline on the board.
    INSERT INTO public.notifications (user_id, category, title, message)
    SELECT s.owner_id, 'reservations',
           'Pickup hold extended',
           'A customer extended a hold on ' || v_row.quantity || ' × size ' ||
           v_row.size || ' to ' ||
           to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC.'
    FROM public.stores s
    WHERE s.id = v_row.store_id AND s.owner_id IS NOT NULL;

    RETURN v_deadline;
END;
$$;

REVOKE ALL ON FUNCTION public.extend_pickup_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extend_pickup_reservation TO authenticated;

-- 8. CANCEL (customer OR seller) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_pickup_reservation(
    p_reservation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor       UUID := auth.uid();
    v_reservation public.pickup_reservations%ROWTYPE;
    v_is_seller   BOOLEAN;
    v_owner_id    UUID;
    v_recipient   UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.pickup_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    SELECT s.owner_id INTO v_owner_id
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    v_is_seller := (v_owner_id IS NOT NULL AND v_owner_id = v_actor);

    IF v_reservation.customer_id <> v_actor AND NOT v_is_seller THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    -- Raise (rather than no-op) so the UI can say "this hold is already
    -- resolved" instead of pretending the cancel worked.
    IF v_reservation.status <> 'active' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    PERFORM public._release_pickup_reservation_stock(
        p_reservation_id, 'active', 'cancelled');

    -- Notify the OTHER party.
    --
    -- ⚠️ THE RECIPIENT CAN BE NULL HERE, and resolving it first is the point.
    -- `is_seller` is only ever true for a store that HAS an owner, so the
    -- customer branch always has somebody to tell — but when the CUSTOMER
    -- cancels a hold at a store whose `owner_id` is NULL (`stores.owner_id` is
    -- NULLABLE), the ELSE branch evaluates to NULL against a NOT NULL column.
    -- Unguarded, that would raise 23502 and stop a customer from cancelling
    -- their own hold. Nobody to notify is not an error: the stock is released
    -- either way. See docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md.
    v_recipient := CASE WHEN v_is_seller THEN v_reservation.customer_id
                        ELSE v_owner_id END;

    IF v_recipient IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_recipient,
            'reservations',
            'Pickup reservation cancelled',
            CASE WHEN v_is_seller
                 THEN 'The store released your pickup hold of ' || v_reservation.quantity ||
                      ' × ' || v_reservation.size || ' (' || v_reservation.product_id || ').'
                 ELSE 'The customer cancelled their pickup hold of ' ||
                      v_reservation.quantity || ' unit(s) — the stock is back on the shelf.'
            END
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_pickup_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_pickup_reservation TO authenticated;

-- 9. FULFILL (seller) — "customer arrived" ────────────────────────────
-- Records the pickup as a REAL POS sale:
--
--   source = 'pos'         the store's in-person sale path. `SalesService`
--                          reads POS sales as `orders WHERE source = 'pos'`
--                          (that is the LIVE path — `sales_transactions` is
--                          legacy), so a fulfilled pickup appears in POS
--                          sales, revenue and `units_sold` with no new
--                          aggregation anywhere.
--   status = 'received'    the terminal state POS orders are inserted with.
--   payment_status='paid'  money changed hands at the counter — the seller
--                          confirming handover is that statement. The
--                          method is the seller's choice (cash by default).
--
-- So the STEP 6 DECISION is: **yes, a fulfilled pickup counts toward
-- `units_sold`** — by construction, because `fetchUnitsSold()` sums
-- `order_items.quantity` over paid, non-cancelled orders and this creates
-- exactly that. It is the same rule the POS already used, rather than a new
-- exception for this feature. Bulk reservations still do not count, because
-- they record no sale at all.
--
-- INVENTORY IS NOT TOUCHED HERE. The units left `inventory.stock` when the
-- hold was created; this converts the hold into the sale. See the header.
CREATE OR REPLACE FUNCTION public.fulfill_pickup_reservation(
    p_reservation_id UUID,
    p_payment_method TEXT DEFAULT 'cash'
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seller      UUID := auth.uid();
    v_reservation public.pickup_reservations%ROWTYPE;
    v_product     public.products%ROWTYPE;
    v_method      TEXT := lower(btrim(COALESCE(p_payment_method, 'cash')));
    v_unit_price  NUMERIC;
    v_total       NUMERIC;
    v_order_id    UUID;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;
    IF v_method NOT IN ('cash', 'gcash') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_METHOD';
    END IF;

    SELECT * INTO v_reservation FROM public.pickup_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                        -- serialize against cancel/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    -- An `active` hold is fulfillable even a little past its deadline (the
    -- customer is standing at the counter and the sweep may not have run
    -- yet). A hold the sweep already released is NOT: those units are back
    -- on the shelf and may be gone.
    IF v_reservation.status <> 'active' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    SELECT * INTO v_product FROM public.products WHERE id = v_reservation.product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;

    -- Price comes from the SERVER (the shared sale-price helper), so a
    -- client cannot propose what the sale was worth.
    v_unit_price := public.product_effective_price(
        v_product.price, v_product.sale_price,
        v_product.sale_starts_at, v_product.sale_ends_at, now());
    v_total := v_unit_price * v_reservation.quantity;

    INSERT INTO public.orders (
        customer_id, store_id, status, fulfillment,
        total_amount, payment_method, payment_status,
        notes, source
    ) VALUES (
        v_reservation.customer_id, v_reservation.store_id, 'received', 'pickup',
        v_total, v_method, 'paid',
        'Collected in store from pickup reservation ' || v_reservation.id,
        'pos'
    ) RETURNING id INTO v_order_id;

    INSERT INTO public.order_items (
        order_id, product_id, size, quantity, unit_price
    ) VALUES (
        v_order_id, v_reservation.product_id, v_reservation.size,
        v_reservation.quantity, v_unit_price
    );

    -- POS orders are inserted directly as 'received', so the AFTER UPDATE
    -- status trigger never fires — write the first history row explicitly,
    -- exactly as the checkout does for POS sales. (`order_id` is a uuid;
    -- the app's own POS history write parses it as an int and therefore
    -- never lands, which is why this is done here instead.)
    INSERT INTO public.order_status_history (order_id, status, changed_at)
    VALUES (v_order_id, 'received', timezone('utc'::text, now()));

    UPDATE public.pickup_reservations
    SET status = 'fulfilled',
        fulfilled_at = timezone('utc'::text, now()),
        fulfilled_order_id = v_order_id
    WHERE id = p_reservation_id;

    INSERT INTO public.notifications (user_id, category, title, message, order_id)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Pickup completed',
        'Your pickup hold was collected — ' || v_reservation.quantity || ' × ' ||
        v_product.name || ' (size ' || v_reservation.size || '). Thank you!',
        v_order_id
    );

    INSERT INTO public.notifications (user_id, category, title, message, order_id)
    SELECT s.owner_id, 'reservations',
           'Pickup sale recorded',
           'Sold ' || v_reservation.quantity || ' × ' || v_product.name ||
           ' (size ' || v_reservation.size || ') — recorded as a POS sale.',
           v_order_id
    FROM public.stores s
    WHERE s.id = v_reservation.store_id AND s.owner_id IS NOT NULL;

    RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fulfill_pickup_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fulfill_pickup_reservation TO authenticated;

-- 10. EXPIRY SWEEP ────────────────────────────────────────────────────
-- NO pg_cron in this database (see 20260907000000_fix_stale_pending_gcash_intents.sql),
-- so this is the same OPPORTUNISTIC sweep the bulk flow uses: the app calls
-- it on the reservations screens and any later call finishes the job.
-- Idempotent and concurrency-safe: every row is handled through the shared
-- release core, which no-ops once the status has moved on, and
-- `FOR UPDATE SKIP LOCKED` lets two callers run at once without blocking.
CREATE OR REPLACE FUNCTION public.expire_pickup_reservations()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_row     RECORD;
    v_owner   UUID;
    v_expired INTEGER := 0;
BEGIN
    FOR v_row IN (
        SELECT id, customer_id, store_id, product_id, size, quantity
        FROM public.pickup_reservations
        WHERE status = 'active'
          AND pickup_deadline <= timezone('utc'::text, now())
        FOR UPDATE SKIP LOCKED
    ) LOOP
        -- The core re-checks `status = 'active'` under its own lock, so a
        -- cancel/fill that won the race makes this a no-op rather than a
        -- second release.
        IF NOT public._release_pickup_reservation_stock(
                   v_row.id, 'active', 'expired') THEN
            CONTINUE;
        END IF;

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_row.customer_id, 'reservations',
            'Pickup reservation expired',
            'Your 24-hour hold of ' || v_row.quantity || ' unit(s) (size ' ||
            v_row.size || ') expired, so the stock went back on the shelf. '
            'You can reserve again if it is still available.'
        );

        SELECT s.owner_id INTO v_owner FROM public.stores s WHERE s.id = v_row.store_id;
        IF v_owner IS NOT NULL THEN
            INSERT INTO public.notifications (user_id, category, title, message)
            VALUES (
                v_owner, 'reservations',
                'Pickup reservation expired',
                'An uncollected pickup hold of ' || v_row.quantity ||
                ' unit(s) (size ' || v_row.size || ') expired — the stock is back.'
            );
        END IF;

        v_expired := v_expired + 1;
    END LOOP;

    RETURN v_expired;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_pickup_reservations FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_pickup_reservations TO authenticated;

-- 11. T-2h REMINDER SWEEP ─────────────────────────────────────────────
-- Same opportunistic pattern. `reminder_sent_at` is the exactly-once guard:
-- a row that already got its reminder is never selected again, so calling
-- this on every screen load cannot spam the customer.
--
-- BOTH SIDES ARE REMINDED, in deliberately different shapes:
--
--   customer  ONE notification PER HOLD ("pick up X by 17:30") — they have a
--             single decision to make about a specific pair, and they may be
--             holding nothing else.
--   store     ONE AGGREGATE notification per owner per run, counting only the
--             rows THIS run claimed ("3 holds expire in the next 2 hours — 4
--             pairs return to stock"). A seller with twenty holds must not
--             receive twenty notifications, and what they need to act on is the
--             BATCH: which holds lapse and how much stock comes back.
--
-- The aggregate inherits the same exactly-once property from the per-row
-- stamp: a second sequential run claims nothing, so it sends no summary. Two
-- CONCURRENT runs each claim a disjoint subset and therefore each summarise
-- their own share — bounded, and never a duplicate row.
CREATE OR REPLACE FUNCTION public.send_pickup_reservation_reminders()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_row     RECORD;
    v_sent    INTEGER := 0;
    -- Accumulated per owner: parallel arrays, so this needs no temp table
    -- (and therefore no lifetime to get wrong).
    v_owners  UUID[] := ARRAY[]::uuid[];
    v_holds   INTEGER[] := ARRAY[]::integer[];
    v_units   INTEGER[] := ARRAY[]::integer[];
    v_at      INTEGER;
BEGIN
    FOR v_row IN (
        SELECT r.id, r.customer_id, r.store_id, r.size, r.quantity,
               r.pickup_deadline,
               p.name AS product_name, s.name AS store_name,
               s.owner_id
        FROM public.pickup_reservations r
        JOIN public.products p ON p.id = r.product_id
        LEFT JOIN public.stores s ON s.id = r.store_id
        WHERE r.status = 'active'
          AND r.reminder_sent_at IS NULL
          AND r.pickup_deadline > timezone('utc'::text, now())
          AND r.pickup_deadline <= timezone('utc'::text, now()) + interval '2 hours'
        FOR UPDATE OF r SKIP LOCKED
    ) LOOP
        -- Stamp first: even a duplicated concurrent call cannot double-send,
        -- because the second caller's SELECT (or this UPDATE) finds it set.
        UPDATE public.pickup_reservations
        SET reminder_sent_at = timezone('utc'::text, now())
        WHERE id = v_row.id AND reminder_sent_at IS NULL;

        IF NOT FOUND THEN
            CONTINUE;                  -- another caller claimed it
        END IF;

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_row.customer_id, 'reservations',
            'Your pickup hold expires soon',
            'Pick up ' || v_row.quantity || ' × ' || v_row.product_name ||
            ' (size ' || v_row.size || ') from ' || COALESCE(v_row.store_name, 'the store') ||
            ' by ' || to_char(v_row.pickup_deadline AT TIME ZONE 'UTC', 'HH24:MI') ||
            ' UTC — after that the hold is released.'
        );

        -- Accumulate for the seller summary. A row with no resolvable owner
        -- (a store whose owner_id is NULL) is still reminded to the customer
        -- but is left OUT of the summary: `notifications.user_id` is NOT NULL,
        -- so one such row would abort the entire sweep — and take every other
        -- store's reminders down with it.
        --
        -- `stores.owner_id` is nullable but its FK is plain NO ACTION, so an
        -- ownerless store is not reachable through the app today. This is a
        -- DEFENSIVE guard, not a live branch (the pgTAP suite asserts the
        -- property by inserting the state directly). Every seller notification
        -- in this file carries the same guard, so no path can abort on it.
        IF v_row.owner_id IS NOT NULL THEN
            v_at := array_position(v_owners, v_row.owner_id);
            IF v_at IS NULL THEN
                v_owners := v_owners || v_row.owner_id;
                v_holds  := v_holds  || 1;
                v_units  := v_units  || v_row.quantity;
            ELSE
                v_holds[v_at] := v_holds[v_at] + 1;
                v_units[v_at] := v_units[v_at] + v_row.quantity;
            END IF;
        END IF;

        v_sent := v_sent + 1;
    END LOOP;

    -- ONE summary per store owner, from this run's claims only.
    FOR v_at IN 1 .. COALESCE(array_length(v_owners, 1), 0) LOOP
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_owners[v_at], 'reservations',
            'Pickup holds expiring soon',
            v_holds[v_at] || CASE WHEN v_holds[v_at] = 1
                                  THEN ' pickup hold expires' ELSE ' pickup holds expire' END ||
            ' in the next 2 hours — ' || v_units[v_at] ||
            CASE WHEN v_units[v_at] = 1
                 THEN ' pair returns' ELSE ' pairs return' END ||
            ' to stock unless collected.'
        );
    END LOOP;

    RETURN v_sent;
END;
$$;

REVOKE ALL ON FUNCTION public.send_pickup_reservation_reminders FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_pickup_reservation_reminders TO authenticated;

-- 12. FOLD THE NEW TABLE INTO THE DEVICE GATE ─────────────────────────
-- `pickup_reservations` is customer-private (it says what someone is
-- holding), so it must be gated like the other private tables rather than
-- exempted. The gate's policy sweep only covers tables that existed when it
-- ran, so a migration that adds an RLS table has to call it — this is the
-- documented procedure, and the pgTAP invariant
-- ("every RLS table is either gated or explicitly exempt") fails if it is
-- forgotten.
SELECT public.install_device_gate_policies();

-- ══════════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════════
-- PREFLIGHT — ONLY IF `pickup_reservations` ALREADY EXISTS, because an earlier
-- revision of this file was applied here first. `CREATE TABLE IF NOT EXISTS`
-- adds nothing to an existing table, so check the two ways a re-apply can still
-- fail: §3b repairs a missing COLUMN, but the unique index below cannot repair
-- DATA.
--
--   1. Columns — all 16 of §3/§3b must be present. Anything missing is exactly
--      what §3b adds, so re-running the file repairs it (this is the shape that
--      produced `42703: column "extension_count" does not exist`):
--        select column_name from information_schema.columns
--         where table_schema = 'public' and table_name = 'pickup_reservations'
--         order by ordinal_position;                       -- expect 16 rows
--
--   2. Duplicate LIVE holds — the partial unique index is created with
--      IF NOT EXISTS, but its data requirement is absolute: two `active` rows
--      for one (customer, product, size) make CREATE UNIQUE INDEX fail. Resolve
--      them first (cancel or expire the newer one) if this returns any row:
--        select customer_id, product_id, size, count(*)
--          from public.pickup_reservations where status = 'active'
--         group by 1, 2, 3 having count(*) > 1;
--
-- The cap is one number everywhere:
--   select public.pickup_reservation_max_quantity();          -- 2
--
-- The hold is real (stock drops by exactly the quantity):
--   select stock from public.inventory where product_id = '<p>' and size = '<s>';
--
-- The window and every budget are one number each:
--   select public.pickup_reservation_hold_hours();             -- 24
--   select public.pickup_reservation_max_extensions();         -- 1
--   select public.pickup_reservation_max_store_extensions();   -- 1
--   select public.pickup_reservation_max_window_hours();       -- 72
-- so a hold can never keep stock for more than 72 hours — the SUM of every
-- budget, enforced by the `pickup_reservations_within_max_window` CHECK (which
-- is built from that function), not only by the RPCs:
--   select public.extend_pickup_reservation('<id>');      -- returns the new deadline
--
-- The T-2h sweep reminds the customer per hold and the store once per batch
-- (returns how many holds were reminded; the store summary is not counted in
-- the return value, which stays "how many customers were notified"):
--   select public.send_pickup_reservation_reminders();
--   select public.request_pickup_reservation('<p>'::uuid, '<s>', 2);
--   select stock from public.inventory where product_id = '<p>' and size = '<s>';
--
-- The table is device-gated (must list exactly one row):
--   select policyname from pg_policies
--    where schemaname = 'public' and tablename = 'pickup_reservations'
--      and policyname = 'Require a trusted device';
--
-- Full proof-of-behaviour: supabase/tests/pickup_reservations.test.sql.
