-- Bulk reservations: the deposit goes from 20% to 70% of the estimated value
-- (quantity × base product price at approval), still rounded UP to a whole
-- peso and still stored resolved.
--
-- Two reasons for the jump: at 20% a reseller could walk away from a 63-unit
-- hold for a fifth of its value, and the store eats the difference when the
-- window expires. 70% is enough that abandoning a hold is a real loss.
--
-- The rate now lives in ONE function, and the customer notification derives
-- its "70%" from it, so the next change is a single-number edit and the copy
-- can never drift from the amount actually charged.
--
-- Replaces the body from 20260913140000_add_bulk_reservation_deposits.sql §5;
-- everything except the rate and its wording is byte-for-byte that function.

CREATE OR REPLACE FUNCTION public.bulk_reservation_deposit_rate()
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT 0.70::numeric
$$;

REVOKE ALL ON FUNCTION public.bulk_reservation_deposit_rate() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bulk_reservation_deposit_rate() TO authenticated;

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
    v_price NUMERIC;
    v_deposit NUMERIC;
    v_deadline TIMESTAMPTZ;
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

    -- ── APPROVE: open the deposit window (NO stock moves yet) ──────
    IF p_days IS NULL OR p_days < 1 THEN
        RAISE EXCEPTION 'INVALID_DEADLINE';
    END IF;

    -- Deposit = bulk_reservation_deposit_rate() of the estimated value
    -- (quantity × product price at approval), rounded UP to a whole peso.
    -- Stored resolved — §2 rule. The ORIGINAL `price` is used, not the sale
    -- price: a reseller hold is priced at pickup, and the sale could expire
    -- before the deposit is even paid. Pinning to the base price keeps
    -- deposit ≠ sale-price arbitrage out of the flow.
    SELECT price INTO v_price
    FROM public.products WHERE id = v_reservation.product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;
    v_deposit := ceil(v_price * v_reservation.quantity
                      * public.bulk_reservation_deposit_rate());

    -- Deposit window: 24 hours from approval (§2 default).
    v_deadline := timezone('utc'::text, now()) + interval '24 hours';

    UPDATE public.bulk_reservations
    SET status = 'awaiting_deposit',
        deposit_amount = v_deposit,
        deposit_status = 'unpaid',
        deposit_deadline = v_deadline,
        -- Seller's chosen hold window, stored exactly as the old flow
        -- did; it becomes operative only when the deposit is confirmed.
        expires_at = timezone('utc'::text, now()) + make_interval(days => p_days)
    WHERE id = p_reservation_id;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation approved — deposit required',
        'Your reservation of ' || v_reservation.quantity || ' units was ' ||
        'approved. Pay the ₱' || v_deposit::int ||
        ' GCash deposit (' ||
        round(public.bulk_reservation_deposit_rate() * 100)::int || '% of the ' ||
        'estimated value) by ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') ||
        ' UTC to hold the stock. The deposit is NON-REFUNDABLE once paid.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.decide_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_bulk_reservation TO authenticated;
