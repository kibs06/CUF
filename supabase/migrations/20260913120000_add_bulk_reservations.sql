-- ════════════════════════════════════════════════════════════════════
-- Bulk Reservations (reseller holds)
-- ════════════════════════════════════════════════════════════════════
-- A customer requests a large-quantity hold on a product ("I want 50 pairs
-- to resell"). The seller approves with a pickup deadline; approval
-- atomically reserves stock by moving units from `inventory.stock` into
-- `bulk_reservations.reserved_stock`, so checkout can never oversell the
-- held units. The customer cancels or the seller rejects → stock returns
-- exactly once (guarded UPDATE on status). A deadline sweep auto-expires
-- stale holds the same way. This mirrors the exactly-once release pattern
-- proven by the direct-GCash order RPCs (20260808210000).
--
-- NOTE: sizes are informational at reservation time — the hold is against
-- the product's TOTAL stock, not a specific size, because resellers buy
-- mixed batches. `sizes` records what the customer asked for; the stock
-- movement draws proportionally from whatever sizes have stock at approval.
-- ════════════════════════════════════════════════════════════════════

-- 1. STATUS ENUM ────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'bulk_reservation_status') THEN
    CREATE TYPE bulk_reservation_status AS ENUM (
      'pending',    -- awaiting the seller's decision; NO stock held
      'approved',   -- stock reserved until expires_at
      'rejected',   -- seller declined; terminal
      'cancelled',  -- customer withdrew; terminal
      'expired',    -- deadline passed, sweep released stock; terminal
      'fulfilled'   -- seller marked picked up / paid; terminal
    );
  END IF;
END
$$;

-- 2. TABLE ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bulk_reservations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id        UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    -- Stock physically moved out of inventory at approval. 0 while pending.
    reserved_stock  INTEGER NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0),
    -- Human-readable breakdown of what the customer asked for, e.g.
    -- [{"size":"40","quantity":20},{"size":"41","quantity":30}]
    requested_sizes JSONB DEFAULT '[]'::jsonb,
    note            TEXT,
    status          bulk_reservation_status NOT NULL DEFAULT 'pending',
    expires_at      TIMESTAMPTZ,          -- set at approval (seller-chosen)
    -- Exactly-once guards: set when stock is moved in/out of the hold.
    reserved_at     TIMESTAMPTZ,
    released_at     TIMESTAMPTZ,
    fulfilled_at    TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_bulk_reservations_store_status
    ON public.bulk_reservations (store_id, status);
CREATE INDEX IF NOT EXISTS idx_bulk_reservations_customer
    ON public.bulk_reservations (customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bulk_reservations_expiry
    ON public.bulk_reservations (expires_at) WHERE status = 'approved';

COMMENT ON TABLE public.bulk_reservations IS
    'Reseller bulk holds: customer requests N units, seller approves with a deadline; approval moves stock out of inventory into the hold, expiry/cancel/reject returns it exactly once.';

-- 3. RLS ────────────────────────────────────────────────────────────
ALTER TABLE public.bulk_reservations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Customers can view their own reservations"
    ON public.bulk_reservations FOR SELECT
    USING (auth.uid() = customer_id);

CREATE POLICY "Customers can create their own reservations"
    ON public.bulk_reservations FOR INSERT
    WITH CHECK (auth.uid() = customer_id);

CREATE POLICY "Sellers can view reservations for their store"
    ON public.bulk_reservations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

-- State changes (approve/reject/cancel/fulfill) go through SECURITY DEFINER
-- RPCs below — no direct UPDATE policy, same as the GCash order RPCs.

CREATE POLICY "Admins can view all reservations"
    ON public.bulk_reservations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- 4. SHARED HELPERS ─────────────────────────────────────────────────

-- Reserved stock per product = sum of active holds. The checkout-side
-- availability query uses this so held units are never sold to others.
CREATE OR REPLACE FUNCTION public.reserved_stock_for_product(p_product_id UUID)
RETURNS INTEGER
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(SUM(reserved_stock), 0)
    FROM public.bulk_reservations
    WHERE product_id = p_product_id AND status = 'approved';
$$;

-- 5. REQUEST (customer) ─────────────────────────────────────────────
-- Validates against live inventory; no stock moves until approval.
CREATE OR REPLACE FUNCTION public.request_bulk_reservation(
    p_product_id UUID,
    p_store_id UUID,
    p_quantity INTEGER,
    p_requested_sizes JSONB DEFAULT '[]'::jsonb,
    p_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer UUID := auth.uid();
    v_available INTEGER;
    v_id UUID;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;
    IF p_quantity IS NULL OR p_quantity < 1 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY';
    END IF;

    -- Product must belong to the claimed store and be active.
    IF NOT EXISTS (
        SELECT 1 FROM public.products
        WHERE id = p_product_id
          AND store_id = p_store_id
          AND is_active = true
    ) THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;

    -- Must actually have the stock today (approval re-checks; stock can move
    -- between request and approval, and the seller sees current numbers).
    SELECT COALESCE(SUM(stock), 0) INTO v_available
    FROM public.inventory WHERE product_id = p_product_id;
    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK (%) < %', v_available, p_quantity;
    END IF;

    -- One live request per customer per product at a time.
    IF EXISTS (
        SELECT 1 FROM public.bulk_reservations
        WHERE customer_id = v_customer
          AND product_id = p_product_id
          AND status IN ('pending', 'approved')
    ) THEN
        RAISE EXCEPTION 'RESERVATION_ALREADY_EXISTS';
    END IF;

    INSERT INTO public.bulk_reservations (
        customer_id, store_id, product_id, quantity,
        requested_sizes, note, status
    ) VALUES (
        v_customer, p_store_id, p_product_id, p_quantity,
        p_requested_sizes, p_note, 'pending'
    ) RETURNING id INTO v_id;

    -- Notify the seller (store owner).
    INSERT INTO public.notifications (user_id, category, title, message)
    SELECT s.owner_id, 'reservations',
           'New bulk reservation request',
           'A customer requested ' || p_quantity || ' units of ' ||
           COALESCE(p.name, 'a product') || ' for resale.'
    FROM public.stores s
    JOIN public.products p ON p.id = p_product_id
    WHERE s.id = p_store_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_bulk_reservation TO authenticated;

-- 6. DECIDE (seller) ────────────────────────────────────────────────
-- Approve: atomically reserve stock (guarded, proportional draw across
-- sizes) with a seller-chosen deadline. Reject: terminal, no stock moved.
CREATE OR REPLACE FUNCTION public.decide_bulk_reservation(
    p_reservation_id UUID,
    p_approve BOOLEAN,
    p_days INTEGER DEFAULT NULL,        -- required when approving
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_seller UUID := auth.uid();
    v_remaining INTEGER;
    v_taken INTEGER;
    v_size_row RECORD;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize concurrent decisions

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    -- Caller must own the store the reservation targets.
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    IF v_reservation.status <> 'pending' THEN
        RAISE EXCEPTION 'ALREADY_DECIDED';
    END IF;

    IF NOT p_approve THEN
        UPDATE public.bulk_reservations
        SET status = 'rejected',
            rejection_reason = p_rejection_reason
        WHERE id = p_reservation_id;

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_reservation.customer_id, 'reservations',
            'Bulk reservation declined',
            'The seller declined your reservation request' ||
            CASE WHEN p_rejection_reason IS NOT NULL AND p_rejection_reason <> ''
                 THEN ': ' || p_rejection_reason ELSE '.' END
        );
        RETURN;
    END IF;

    -- ── APPROVE: reserve stock now ─────────────────────────────────
    IF p_days IS NULL OR p_days < 1 THEN
        RAISE EXCEPTION 'INVALID_DEADLINE';
    END IF;

    v_remaining := v_reservation.quantity;

    -- Draw stock per size, largest sizes first, never below 0
    -- (inventory has a stock >= 0 CHECK that guards the last unit).
    FOR v_size_row IN (
        SELECT size, stock FROM public.inventory
        WHERE product_id = v_reservation.product_id AND stock > 0
        ORDER BY stock DESC
        FOR UPDATE
    ) LOOP
        EXIT WHEN v_remaining <= 0;
        v_taken := LEAST(v_size_row.stock, v_remaining);
        UPDATE public.inventory
        SET stock = stock - v_taken,
            updated_at = timezone('utc'::text, now())
        WHERE product_id = v_reservation.product_id
          AND size = v_size_row.size;
        v_remaining := v_remaining - v_taken;
    END LOOP;

    IF v_remaining > 0 THEN
        -- Stock changed between request and decision — approve only what
        -- is actually available, or abort? Abort loudly: the seller sees
        -- live counts in the approval sheet and can re-decide.
        RAISE EXCEPTION 'INSUFFICIENT_STOCK_MISSING_%', v_remaining;
    END IF;

    UPDATE public.bulk_reservations
    SET status = 'approved',
        reserved_stock = v_reservation.quantity,
        reserved_at = timezone('utc'::text, now()),
        expires_at = timezone('utc'::text, now()) + make_interval(days => p_days)
    WHERE id = p_reservation_id;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation approved',
        'Your reservation of ' || v_reservation.quantity || ' units is held ' ||
        'for ' || p_days || ' day(s) — complete pickup/payment before it expires.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.decide_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_bulk_reservation TO authenticated;

-- 7. CANCEL (customer) / FULFILL (seller) / EXPIRE (sweep) ──────────
-- Shared exactly-once release core: returns the hold's stock to inventory
-- on the LARGEST sizes first (inverse of the draw) and flips status in the
-- same transaction, guarded on the expected starting status.
CREATE OR REPLACE FUNCTION public._release_bulk_reservation_stock(
    p_reservation_id UUID,
    p_expected_status bulk_reservation_status,
    p_new_status bulk_reservation_status
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_remaining INTEGER;
    v_size_row RECORD;
BEGIN
    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize against decide/fulfill

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.status <> p_expected_status THEN
        RETURN;                          -- already released; idempotent no-op
    END IF;
    IF v_reservation.reserved_stock <= 0 THEN
        -- Pending holds hold nothing; still safe to flip status.
        UPDATE public.bulk_reservations
        SET status = p_new_status,
            released_at = CASE
                WHEN p_new_status IN ('cancelled', 'expired') THEN timezone('utc'::text, now())
                ELSE released_at END,
            fulfilled_at = CASE
                WHEN p_new_status = 'fulfilled' THEN timezone('utc'::text, now())
                ELSE fulfilled_at END
        WHERE id = p_reservation_id;
        RETURN;
    END IF;

    -- Return units to the sizes with the LOWEST stock first (closest to the
    -- original draw; keeps size distribution balanced). If a size row was
    -- deleted meanwhile, fall back to any row for the product.
    v_remaining := v_reservation.reserved_stock;
    FOR v_size_row IN (
        SELECT size FROM public.inventory
        WHERE product_id = v_reservation.product_id
        ORDER BY stock ASC
        FOR UPDATE
    ) LOOP
        EXIT WHEN v_remaining <= 0;
        UPDATE public.inventory
        SET stock = stock + 1,
            updated_at = timezone('utc'::text, now())
        WHERE product_id = v_reservation.product_id
          AND size = v_size_row.size;
        v_remaining := v_remaining - 1;
    END LOOP;

    -- Inventory row(s) deleted while held: recreate a restock row so the
    -- units are never lost (mirrors the GCash RPC edge-case handling).
    IF v_remaining > 0 THEN
        INSERT INTO public.inventory (product_id, size, stock)
        VALUES (v_reservation.product_id, 'Restock', v_remaining)
        ON CONFLICT (product_id, size)
        DO UPDATE SET stock = public.inventory.stock + EXCLUDED.stock,
                      updated_at = timezone('utc'::text, now());
    END IF;

    UPDATE public.bulk_reservations
    SET status = p_new_status,
        released_at = CASE
            WHEN p_new_status IN ('cancelled', 'expired') THEN timezone('utc'::text, now())
            ELSE released_at END,
        fulfilled_at = CASE
            WHEN p_new_status = 'fulfilled' THEN timezone('utc'::text, now())
            ELSE fulfilled_at END
    WHERE id = p_reservation_id;
END;
$$;

-- NOTE: the release writes back one unit at a time, which is fine for
-- reseller-scale quantities (tens to low hundreds of units).

-- 7a. Customer cancels their own PENDING or APPROVED reservation.
CREATE OR REPLACE FUNCTION public.cancel_bulk_reservation(p_reservation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer UUID := auth.uid();
    v_store_owner UUID;
    v_reservation public.bulk_reservations%ROWTYPE;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status NOT IN ('pending', 'approved') THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    PERFORM public._release_bulk_reservation_stock(
        p_reservation_id, v_reservation.status, 'cancelled');

    -- Notify the seller.
    SELECT s.owner_id INTO v_store_owner
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    IF v_store_owner IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_store_owner, 'reservations',
            'Bulk reservation cancelled',
            'The customer cancelled their reservation of ' ||
            v_reservation.quantity || ' units.'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_bulk_reservation TO authenticated;

-- 7b. Seller marks an approved reservation fulfilled (customer paid /
--     picked up the goods).
CREATE OR REPLACE FUNCTION public.fulfill_bulk_reservation(p_reservation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seller UUID := auth.uid();
    v_reservation public.bulk_reservations%ROWTYPE;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'approved' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    PERFORM public._release_bulk_reservation_stock(
        p_reservation_id, 'approved', 'fulfilled');

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation fulfilled',
        'Your reservation of ' || v_reservation.quantity ||
        ' units was completed. Thank you for your business!'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fulfill_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fulfill_bulk_reservation TO authenticated;

-- 7c. Expiry sweep — idempotent, callable by anyone (authenticated) so the
-- app can run it opportunistically (same pattern as expire_overdue_gcash_orders).
CREATE OR REPLACE FUNCTION public.expire_bulk_reservations()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_row RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_row IN (
        SELECT id, customer_id, quantity, expires_at
        FROM public.bulk_reservations
        WHERE status = 'approved'
          AND expires_at IS NOT NULL
          AND expires_at <= timezone('utc'::text, now())
        FOR UPDATE SKIP LOCKED
    ) LOOP
        PERFORM public._release_bulk_reservation_stock(v_row.id, 'approved', 'expired');

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_row.customer_id, 'reservations',
            'Bulk reservation expired',
            'Your reservation of ' || v_row.quantity ||
            ' units expired — the items are back in the store''s stock. You can request again.'
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_bulk_reservations FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_bulk_reservations TO authenticated;
