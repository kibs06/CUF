-- ══════════════════════════════════════════════════════════════════════
-- Pickup holds name the colour they are holding
-- ══════════════════════════════════════════════════════════════════════
-- A pickup hold was `(customer, product, size, quantity)` — and a product sold
-- in three colours is three different pairs of shoes on the shelf. The seller
-- read "hold 1 × EU 41" and had to guess (or message the customer) which one to
-- set aside, while the customer's app was showing them a colour the whole time
-- (`variants.color`, and the detail page's picker).
--
-- So the hold records the colour the customer chose. It is INFORMATIONAL:
--
--   • the hold, the stock check, the compare-and-set and the one-live-hold
--     index all stay keyed on `(product_id, size)` — `inventory` has no colour
--     dimension, and `20260915170000` §3 explains why a hold draws from the
--     size's stock. Making the colour load-bearing would mean re-keying
--     inventory, which is a different feature with a migration of its own;
--   • a colour is NOT validated against `product_variants`. The variant list is
--     a seller-editable display aid, and a hold must not fail because a variant
--     row was renamed between the customer opening the page and tapping
--     Reserve. The worst case of a stale name is a seller reading it and
--     pulling the wrong shade — which they can already do today with no name at
--     all;
--   • NULL is the norm for rows that predate this column, and for products
--     without colour variants. Every reader renders "nothing" rather than a
--     placeholder.
--
-- WHY THE FUNCTION IS DROPPED AND RECREATED: Postgres resolves `request_
-- pickup_reservation(a, b, c)` against BOTH the existing 3-argument function and
-- a new 4-argument one whose last parameter has a DEFAULT — that is an
-- ambiguous call ("function is not unique", 42725), not a preference. The old
-- signature is therefore dropped first, and the new one carries the DEFAULT so
-- every existing client (PostgREST resolves by argument NAME) keeps working
-- untouched.
-- ══════════════════════════════════════════════════════════════════════

-- 1. THE COLUMN ────────────────────────────────────────────────────────
ALTER TABLE public.pickup_reservations
    ADD COLUMN IF NOT EXISTS color TEXT;

COMMENT ON COLUMN public.pickup_reservations.color IS
  'Variant colour the customer chose, as the seller named it (product_variants.color). Informational: the hold and its stock check are keyed on (product_id, size) because inventory is colour-blind. NULL for colourless products and for rows that predate this column.';

-- 2. REQUEST (customer) — now carries the colour ───────────────────────
-- Body is byte-for-byte the version in `20260915170000` §7 except for
-- `p_color`, the `v_color` normalisation, the INSERT's colour column and the
-- two notifications, which now name the colour so the seller notification is
-- actionable on its own.
DROP FUNCTION IF EXISTS public.request_pickup_reservation(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.request_pickup_reservation(
    p_product_id UUID,
    p_size TEXT,
    p_quantity INTEGER DEFAULT 1,
    p_color TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer  UUID := auth.uid();
    v_product   public.products%ROWTYPE;
    v_cap       INTEGER := public.pickup_reservation_max_quantity();
    v_size      TEXT := btrim(COALESCE(p_size, ''));
    v_color     TEXT := NULLIF(btrim(COALESCE(p_color, '')), '');
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
    -- allowed once the previous hold resolves. Deliberately blind to COLOUR:
    -- two colours of the same size are the same shelf slot to this check.
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
        customer_id, store_id, product_id, size, color, quantity,
        reserved_stock, status, pickup_deadline, reserved_at
    ) VALUES (
        v_customer, v_product.store_id, p_product_id, v_resolved, v_color,
        p_quantity, p_quantity, 'active', v_deadline,
        timezone('utc'::text, now())
    ) RETURNING id INTO v_id;

    -- Customer confirmation (deadline + what to bring). The colour is echoed
    -- back so the customer can see the hold matched the pair they were
    -- looking at.
    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_customer, 'reservations',
        'Pickup reservation confirmed',
        'We are holding ' || p_quantity || ' × ' || v_product.name ||
        ' (size ' || v_resolved ||
        CASE WHEN v_color IS NULL THEN '' ELSE ', ' || v_color END ||
        ') for you until ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC.'
    );

    -- Seller heads-up: stock is off the shelf, and now WHICH pair came off it.
    INSERT INTO public.notifications (user_id, category, title, message)
    SELECT s.owner_id, 'reservations',
           'New pickup reservation',
           'A customer is holding ' || p_quantity || ' × ' || v_product.name ||
           ' (size ' || v_resolved ||
           CASE WHEN v_color IS NULL THEN '' ELSE ', ' || v_color END ||
           ') for pickup until ' ||
           to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC.'
    -- `owner_id IS NOT NULL` everywhere a store is notified: the column is
    -- nullable, `notifications.user_id` is NOT NULL, and an ownerless store
    -- would abort whatever RPC happened to touch it.
    FROM public.stores s
    WHERE s.id = v_product.store_id AND s.owner_id IS NOT NULL;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_pickup_reservation(UUID, TEXT, INTEGER, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pickup_reservation(UUID, TEXT, INTEGER, TEXT)
    TO authenticated;
