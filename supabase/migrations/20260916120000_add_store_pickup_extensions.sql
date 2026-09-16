-- ══════════════════════════════════════════════════════════════════════
-- Store GOODWILL extensions for pickup holds — the other half of the
-- extension story (ANQUI item 14 follow-up)
-- ══════════════════════════════════════════════════════════════════════
-- Until now only the CUSTOMER could ask for more time
-- (`extend_pickup_reservation`, deliberately customer-only). A store that
-- WANTED to be lenient — "the customer called, they are stuck in traffic, give
-- them another day" — had no way to say yes; the only answer available was
-- "reserve again and hope the size is still there". This file adds that ability,
-- as an explicit, audited, bounded favour rather than by loosening the customer
-- rule:
--
--   EXPLICIT — a separate RPC (`grant_pickup_extension`) that will not proceed
--      without a reason. It is not a door left ajar in the customer path, and
--      the customer path is not widened to match: each side has its own budget.
--
--   AUDITED  — every grant writes a row to
--      `pickup_reservation_extension_grants`: who granted it, for which hold, for
--      which customer and store, from which deadline to which, how many hours,
--      and WHY. A deadline the store cannot explain is the thing this prevents.
--
--   BOUNDED  — the store's own budget, counted in
--      `pickup_reservations.store_extension_count` and capped by a table CHECK
--      against `pickup_reservation_max_store_extensions()`. The store cannot
--      park its own stock indefinitely either: the total window stays bounded by
--      `pickup_reservations_within_max_window` (hold + every budget = 72 h).
--
-- ⚠️ WHY THIS IS A SEPARATE FILE RATHER THAN AN EDIT TO `extend_pickup_
-- reservation`: the two acts are different in kind, and merging them would make
-- the customer's self-service extension and a store's recorded favour
-- indistinguishable in the data. Keeping them apart is what lets the audit trail
-- answer "did the customer ask, or did we give?" — which is the question a
-- disputed deadline actually turns into.
--
-- ⚠️ REQUIREMENT: `20260915170000_add_pickup_reservations.sql` must be re-applied
-- BEFORE this file on a database where the hold system already exists. That file
-- owns the budgets and the window CHECK; it was amended so the ceiling sums
-- every budget (48 h → 72 h). Applying this file alone against an older hold
-- table succeeds, but the first grant would be refused by the stale CHECK. It is
-- re-runnable (§3b converges it), so re-applying is the intended step.
-- ══════════════════════════════════════════════════════════════════════

-- 1. THE TRAIL ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pickup_reservation_extension_grants (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Structural link, and the reason the trail has a lifetime: it exists to
    -- explain a HOLD's deadline, so it travels with the hold. It is not a
    -- compliance archive — deleting the account that owns the reservation takes
    -- its grants with it, exactly as `seller_application_audit_log` does.
    reservation_id    UUID NOT NULL REFERENCES public.pickup_reservations(id) ON DELETE CASCADE,
    -- Denormalised (customer/store), so both sides' histories are single-table
    -- reads and neither policy needs to reach through the reservation:
    -- "everything this store gave away" and "everything this customer was
    -- given" are each one query. Same reasoning as pickup_reservations.store_id.
    customer_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id          UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    -- Who granted it. NULLABLE + SET NULL, matching
    -- `gcash_payment_decision_audit.seller_id`: an admin deleting a seller
    -- account should not delete the record that a favour happened — the row
    -- still carries WHAT was granted and WHY, which is what it is for.
    granted_by        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    -- The move itself, recorded as a before/after pair rather than only the
    -- delta: a deadline can be explained from one row without reconstructing
    -- the sequence of grants.
    previous_deadline TIMESTAMPTZ NOT NULL,
    new_deadline      TIMESTAMPTZ NOT NULL,
    hours_granted     INTEGER NOT NULL CHECK (hours_granted > 0),
    -- Required, and short by construction: a reason long enough to mean
    -- something, short enough that it stays a reason. Enforced here AND in the
    -- RPC (which raises a readable INVALID_REASON first); the CHECK is what
    -- makes an unexplained row impossible to insert by any path.
    reason            TEXT NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 280),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Convergence, for the same reason §3b of the base file exists: this file is
-- hand-applied through the SQL Editor, so `CREATE TABLE IF NOT EXISTS` is a
-- NO-OP on a database that already has the table and would silently keep an
-- older shape (see MIGRATIONS_LIVE_STATUS.md → "a table is not re-created by
-- re-running — it must CONVERGE").
ALTER TABLE public.pickup_reservation_extension_grants
    ADD COLUMN IF NOT EXISTS id                UUID DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS reservation_id    UUID NOT NULL REFERENCES public.pickup_reservations(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS customer_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS store_id          UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS granted_by        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS previous_deadline TIMESTAMPTZ NOT NULL,
    ADD COLUMN IF NOT EXISTS new_deadline      TIMESTAMPTZ NOT NULL,
    ADD COLUMN IF NOT EXISTS hours_granted     INTEGER NOT NULL CHECK (hours_granted > 0),
    ADD COLUMN IF NOT EXISTS reason            TEXT NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 280),
    ADD COLUMN IF NOT EXISTS created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now());

-- …and the two column CHECKs, explicitly, for the same reason §3b of the base
-- file lists its counters: an inline CHECK exists only WITH its column, so
-- `ADD COLUMN IF NOT EXISTS` is a no-op on a table that already has the column
-- and a missing CHECK would stay missing. The REASON being a constraint is the
-- whole point of this table, so it must survive a re-apply.
ALTER TABLE public.pickup_reservation_extension_grants
    DROP CONSTRAINT IF EXISTS pickup_reservation_extension_grants_hours_granted_check;
ALTER TABLE public.pickup_reservation_extension_grants
    ADD CONSTRAINT pickup_reservation_extension_grants_hours_granted_check
    CHECK (hours_granted > 0);
ALTER TABLE public.pickup_reservation_extension_grants
    DROP CONSTRAINT IF EXISTS pickup_reservation_extension_grants_reason_check;
ALTER TABLE public.pickup_reservation_extension_grants
    ADD CONSTRAINT pickup_reservation_extension_grants_reason_check
    CHECK (length(btrim(reason)) BETWEEN 3 AND 280);

-- A hold's own history (the tile reads the latest), and a store's giving history.
CREATE INDEX IF NOT EXISTS idx_pickup_extension_grants_reservation
    ON public.pickup_reservation_extension_grants (reservation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pickup_extension_grants_store
    ON public.pickup_reservation_extension_grants (store_id, created_at DESC);

COMMENT ON TABLE public.pickup_reservation_extension_grants IS
  'Audit trail of GOODWILL extensions a store granted on a pickup hold: who, when, from which deadline to which, how many hours, and why. Separate from the customer''s own extension (which is recorded by extension_count on the hold and needs no justification) so a disputed deadline can be explained.';
COMMENT ON COLUMN public.pickup_reservation_extension_grants.reason IS
  'Required (3-280 chars). The difference between a goodwill gesture and an unexplained deadline change.';

-- 2. RLS ──────────────────────────────────────────────────────────────
-- SELECT only, for the three audiences — the same shape as the hold table
-- itself, and for the same reason: a row here records something that already
-- happened, so `grant_pickup_extension` is the only write path and a
-- hand-crafted INSERT cannot fabricate a trail.
ALTER TABLE public.pickup_reservation_extension_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view grants on their own holds"
    ON public.pickup_reservation_extension_grants;
CREATE POLICY "Customers can view grants on their own holds"
    ON public.pickup_reservation_extension_grants FOR SELECT
    USING (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Sellers can view grants for their store"
    ON public.pickup_reservation_extension_grants;
CREATE POLICY "Sellers can view grants for their store"
    ON public.pickup_reservation_extension_grants FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Admins can view all pickup extension grants"
    ON public.pickup_reservation_extension_grants;
CREATE POLICY "Admins can view all pickup extension grants"
    ON public.pickup_reservation_extension_grants FOR SELECT
    USING (public.is_admin());

-- 3. GRANT (store owner only) ─────────────────────────────────────────
-- Rules, each checked under the row lock so two simultaneous taps cannot double
-- a grant (the same class of race as the customer cap and the duplicate-hold
-- index):
--
--   1. ONLY THE STORE THAT OWNS THE HOLD. Not another seller, not the customer
--      (a customer approving their own favour is not a favour), not an admin
--      acting silently — support changes go through the same visible path.
--   2. ONLY WHILE THE HOLD IS LIVE. Once the deadline has passed the hold may
--      lapse at any moment, so adding time could promise stock the sweep is
--      about to release.
--   3. ONLY ONCE per hold, and only a bounded amount (24 h). More than that is
--      not goodwill, it is a bulk reservation with extra steps.
--   4. NEVER WITHOUT A REASON, and it is always recorded.
--
-- Stock is untouched (the units left `inventory.stock` when the hold was created)
-- and nothing is charged. The new deadline is owed its own T-2h warning, so
-- `reminder_sent_at` is cleared exactly as the customer path does.
--
-- Returns the NEW deadline so the caller can show it without a refetch.
CREATE OR REPLACE FUNCTION public.grant_pickup_extension(
    p_reservation_id UUID,
    p_reason TEXT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor     UUID := auth.uid();
    v_row       public.pickup_reservations%ROWTYPE;
    v_reason    TEXT := btrim(COALESCE(p_reason, ''));
    v_max       INTEGER := public.pickup_reservation_max_store_extensions();
    v_added     INTEGER := public.pickup_reservation_store_extension_hours();
    v_deadline  TIMESTAMPTZ;
    v_left      INTEGER;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_row FROM public.pickup_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                        -- serialize against cancel/fulfill/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    -- The store that owns the hold, and only that store: being a seller is not
    -- enough. Mirrors cancel/sweep ownership checks elsewhere in this system.
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_row.store_id AND owner_id = v_actor
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    -- Checked before the state rules so the copy the caller sees is about the
    -- missing reason rather than a hold that may also have moved on.
    IF length(v_reason) < 3 OR length(v_reason) > 280 THEN
        RAISE EXCEPTION 'INVALID_REASON — a goodwill extension needs a short reason (3-280 characters)';
    END IF;

    IF v_row.status <> 'active' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    IF v_row.pickup_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'HOLD_LAPSED — this hold has already run out; ask the customer to reserve again';
    END IF;

    IF v_row.store_extension_count >= v_max THEN
        RAISE EXCEPTION 'STORE_EXTENSION_LIMIT_REACHED (%) — this hold already had a goodwill extension',
            v_max;
    END IF;

    v_deadline := v_row.pickup_deadline + v_added * interval '1 hour';
    v_left     := v_max - (v_row.store_extension_count + 1);

    UPDATE public.pickup_reservations
    SET pickup_deadline       = v_deadline,
        store_extension_count = store_extension_count + 1,
        -- The OLD deadline's reminder does not apply to the NEW one. Clearing it
        -- re-arms the T-2h warning; leaving it set would silently mean the
        -- customer is never warned about the deadline we just granted.
        reminder_sent_at      = NULL
    WHERE id = v_row.id;

    -- THE TRAIL — written in the same transaction as the deadline change, so a
    -- grant can never exist without its record (or the reverse).
    INSERT INTO public.pickup_reservation_extension_grants (
        reservation_id, customer_id, store_id, granted_by,
        previous_deadline, new_deadline, hours_granted, reason
    ) VALUES (
        v_row.id, v_row.customer_id, v_row.store_id, v_actor,
        v_row.pickup_deadline, v_deadline, v_added, v_reason
    );

    -- The customer is told, and told WHY: an unexplained later deadline reads
    -- like a glitch, and the reason is the whole point of making this explicit.
    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_row.customer_id, 'reservations',
        'The store extended your pickup hold',
        'Good news — ' || v_row.quantity || ' unit(s) of size ' || v_row.size ||
        ' are held for you until ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') ||
        ' UTC. The store added ' || v_added || ' hours: ' || v_reason
    );

    RETURN v_deadline;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_pickup_extension FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_pickup_extension TO authenticated;

-- 4. FOLD THE NEW TABLE INTO THE DEVICE GATE ──────────────────────────
-- The trail names a customer and a store, so it is customer-private like the
-- hold table and joins the gate rather than being exempted. The gate's policy
-- sweep only covers tables that existed when it last ran, so a migration that
-- adds an RLS table has to call it — the pgTAP invariant ("every RLS table is
-- either device-gated or explicitly exempt") fails if this is forgotten.
SELECT public.install_device_gate_policies();

-- ══════════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════════
-- The store budget is one number, and the ceiling sums every budget:
--   select public.pickup_reservation_max_store_extensions();   -- 1
--   select public.pickup_reservation_store_extension_hours();  -- 24
--   select public.pickup_reservation_max_window_hours();       -- 72
--
-- A grant moves the deadline by exactly that, records itself, and tells the
-- customer why (run as the store owner):
--   select public.grant_pickup_extension('<reservation-uuid>', 'Customer stuck in traffic');
--   select previous_deadline, new_deadline, hours_granted, reason, granted_by
--     from public.pickup_reservation_extension_grants
--    where reservation_id = '<reservation-uuid>' order by created_at desc;
--
-- The trail is gated (must list exactly one row):
--   select policyname from pg_policies
--    where schemaname = 'public'
--      and tablename = 'pickup_reservation_extension_grants'
--      and policyname = 'Require a trusted device';
--
-- Full proof-of-behaviour: supabase/tests/store_pickup_extensions.test.sql.
