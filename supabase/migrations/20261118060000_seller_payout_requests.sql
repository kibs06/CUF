-- ══════════════════════════════════════════════════════════════════
-- Migration: One owner for the payout math + seller payout requests
-- Date: 2026-11-18
-- Depends on: 20261118050000 (seller_payouts, generate_daily_payouts),
--             20260812000000 (profiles.payout_method / payout_details)
--
-- Part A — the money math lives in exactly one place
--
-- Before this file the per-order split (goods, commission, net) was written out
-- four times: twice inside generate_daily_payouts, once in v_seller_payables and
-- once more in the request RPC added below. Four copies of a rounding rule is a
-- drift bug waiting to happen: the admin's "store balances" number and the
-- batch the same admin generates could disagree by a centavo, and nobody would
-- know which was right.
--
-- seller_payout_amounts(total, bps, delivery) now owns that rule. The nightly
-- generator, the payroll view and the seller request all call it, so changing
-- the rule (a commission rounding fix, say) changes every surface at once.
--
-- Part B — sellers may ask for a payout, admin still settles it
--
-- request_my_payout() batches the caller's own store's already-reconciled
-- orders into today's draft. It never marks anything paid: mark_payout_paid()
-- (admin-only, reference required) is still the only way money is recorded as
-- sent, so the two-person control is intact — the seller chooses *when* to ask,
-- never *whether* the funds are real.
--
-- Two invariants stay true for every writer:
--   • seller_payout_items.UNIQUE(order_id) — an order is payable exactly once.
--   • net_amount is recomputed as the sum of the batch's own lines.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- A1. seller_payout_amounts — THE payout calculation
--
--   goods      = total − delivery            (delivery is the courier's)
--   commission = round(goods × bps / 10000, 2)
--   net        = goods − commission
--
-- IMMUTABLE and pure: same inputs, same answer, no table access. That is what
-- lets a view, a plpgsql generator and a seller-facing RPC share it without any
-- of them being able to disagree.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.seller_payout_amounts(
  p_total    numeric,
  p_bps      integer,
  p_delivery numeric
) RETURNS TABLE (goods numeric, commission numeric, net numeric)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT g.goods,
         round(g.goods * COALESCE(p_bps, 0) / 10000.0, 2)          AS commission,
         round(g.goods - round(g.goods * COALESCE(p_bps, 0) / 10000.0, 2), 2) AS net
    FROM (
      SELECT round(COALESCE(p_total, 0) - COALESCE(p_delivery, 0), 2) AS goods
    ) g
$$;

COMMENT ON FUNCTION public.seller_payout_amounts(numeric, integer, numeric) IS
  'The one payout calculation: goods = total − delivery, commission = round(goods × bps / 10000, 2), net = goods − commission. Used by generate_daily_payouts, request_my_payout and v_seller_payables.';

-- Needed because v_seller_payables runs with the caller's privileges
-- (security_invoker) and calls this function. It is pure arithmetic on
-- caller-supplied numbers, so exposing execute leaks nothing.
REVOKE EXECUTE ON FUNCTION public.seller_payout_amounts(numeric, integer, numeric) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.seller_payout_amounts(numeric, integer, numeric) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- A2. generate_daily_payouts — same behaviour, one calculation
--     Redefined, not moved: 20261118050000 already shipped this function to
--     the hosted project, so it is replaced here rather than edited there.
--     The eligibility predicate and the header/line invariants are unchanged;
--     only the split now comes from seller_payout_amounts().
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_daily_payouts(p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date     date := COALESCE(p_date, (now() AT TIME ZONE 'Asia/Manila')::date);
  v_bps      int;
  v_delivery numeric;
  v_headers  int := 0;
  v_items    int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can generate payouts';
  END IF;

  SELECT COALESCE(platform_fee_bps, 0), COALESCE(delivery_fee_amount, 0)
    INTO v_bps, v_delivery
    FROM public.platform_settings
   WHERE id = 1;
  v_bps := COALESCE(v_bps, 0);
  v_delivery := COALESCE(v_delivery, 0);

  -- 1. Draft header per store that has eligible orders that day.
  WITH eligible AS (
    SELECT o.id,
           o.store_id,
           o.total_amount,
           m.commission,
           m.net
      FROM public.orders o
      CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, v_bps, v_delivery) m
     WHERE o.payment_status = 'paid'
       AND o.payment_method = 'gcash'
       AND o.source = 'online'
       AND o.funds_reconciled_at IS NOT NULL
       AND NOT o.payment_flagged
       AND o.status NOT IN ('cancelled', 'cancellation_requested')
       -- An order that does not even cover the delivery fee has no goods value
       -- to split; it cannot produce a non-negative line, so it is not a payout
       -- candidate (it needs a refund or a cancel, not a transfer).
       AND (o.total_amount - v_delivery) > 0
       AND (o.created_at AT TIME ZONE 'Asia/Manila')::date = v_date
       AND NOT EXISTS (
         SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
       )
  ),
  agg AS (
    SELECT store_id,
           sum(total_amount)::numeric(12,2)        AS gross,
           (count(*) * v_delivery)::numeric(12,2)  AS delivery_total,
           sum(commission)::numeric(12,2)          AS fee,
           sum(net)::numeric(12,2)                 AS net
      FROM eligible
     GROUP BY store_id
  )
  INSERT INTO public.seller_payouts
    (store_id, period_date, gross_amount, delivery_fees, platform_fee, net_amount, created_by)
  SELECT store_id, v_date, gross, delivery_total, fee, net, auth.uid()
    FROM agg
  ON CONFLICT (store_id, period_date) DO NOTHING;

  GET DIAGNOSTICS v_headers = ROW_COUNT;

  -- 2. Attach the orders to their store's draft payout for that day.
  WITH eligible AS (
    SELECT o.id, o.store_id, m.net
      FROM public.orders o
      CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, v_bps, v_delivery) m
     WHERE o.payment_status = 'paid'
       AND o.payment_method = 'gcash'
       AND o.source = 'online'
       AND o.funds_reconciled_at IS NOT NULL
       AND NOT o.payment_flagged
       AND o.status NOT IN ('cancelled', 'cancellation_requested')
       AND (o.total_amount - v_delivery) > 0
       AND (o.created_at AT TIME ZONE 'Asia/Manila')::date = v_date
       AND NOT EXISTS (
         SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
       )
  )
  INSERT INTO public.seller_payout_items (payout_id, order_id, amount)
  SELECT sp.id, e.id, e.net
    FROM eligible e
    JOIN public.seller_payouts sp
      ON sp.store_id = e.store_id
     AND sp.period_date = v_date
     AND sp.status = 'draft'
  ON CONFLICT (order_id) DO NOTHING;

  GET DIAGNOSTICS v_items = ROW_COUNT;

  -- 3. Recompute every draft header for the day from its own lines, so a re-run
  --    adds orders without double-counting. net is the sum of the stored line
  --    amounts (what will actually be paid); commission is the same
  --    seller_payout_amounts() value the lines were built from.
  UPDATE public.seller_payouts sp
     SET gross_amount  = COALESCE(t.gross, 0),
         delivery_fees = COALESCE(t.delivery, 0),
         platform_fee  = COALESCE(t.fee, 0),
         net_amount    = COALESCE(t.net, 0),
         updated_at    = now()
    FROM (
      SELECT i.payout_id,
             sum(o.total_amount)::numeric(12,2)       AS gross,
             (count(*) * v_delivery)::numeric(12,2)   AS delivery,
             sum(m.commission)::numeric(12,2)         AS fee,
             sum(i.amount)::numeric(12,2)             AS net
        FROM public.seller_payout_items i
        JOIN public.orders o ON o.id = i.order_id
        CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, v_bps, v_delivery) m
       WHERE i.payout_id IN (
         SELECT id FROM public.seller_payouts
          WHERE period_date = v_date AND status = 'draft'
       )
       GROUP BY i.payout_id
    ) t
   WHERE sp.id = t.payout_id;

  RETURN jsonb_build_object(
    'period_date', v_date,
    'payouts_created', v_headers,
    'orders_added', v_items
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- A3. v_seller_payables — the "what we still owe" card
--     Same calculation, same eligibility, so the admin's balance number and
--     the batch generated from it can never disagree.
-- ────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.v_seller_payables;
CREATE VIEW public.v_seller_payables
WITH (security_invoker = true) AS
WITH cfg AS (
  SELECT COALESCE(platform_fee_bps, 0) AS bps,
         COALESCE(delivery_fee_amount, 0) AS delivery
    FROM public.platform_settings
   WHERE id = 1
)
SELECT
  o.store_id,
  s.name AS store_name,
  s.owner_id,
  count(*)::int AS order_count,
  sum(o.total_amount)::numeric(12,2) AS gross_amount,
  sum(cfg.delivery)::numeric(12,2) AS delivery_fees,
  sum(m.commission)::numeric(12,2) AS platform_fee,
  sum(m.net)::numeric(12,2) AS net_amount
FROM public.orders o
JOIN public.stores s ON s.id = o.store_id
CROSS JOIN cfg
CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, cfg.bps, cfg.delivery) m
WHERE o.payment_status = 'paid'
  AND o.payment_method = 'gcash'
  AND o.source = 'online'
  AND o.funds_reconciled_at IS NOT NULL
  AND NOT o.payment_flagged
  AND o.status NOT IN ('cancelled', 'cancellation_requested')
  AND (o.total_amount - cfg.delivery) > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
  )
GROUP BY o.store_id, s.name, s.owner_id;

COMMENT ON VIEW public.v_seller_payables IS
  'Reconciled, paid, unbatched online-GCash orders grouped by store — the amounts the platform still owes. Split comes from seller_payout_amounts().';

GRANT SELECT ON public.v_seller_payables TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- B1. Request metadata on the batch header
--     requested_at stays NULL for admin-generated batches, which is what lets
--     the portal label a row "Requested" instead of "Scheduled".
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_payouts
  ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.seller_payouts.requested_at IS
  'When the seller asked for this payout. NULL = generated by the admin nightly batch.';
COMMENT ON COLUMN public.seller_payouts.requested_by IS
  'The seller who requested it (NULL for admin-generated batches).';

CREATE INDEX IF NOT EXISTS idx_seller_payouts_requested
  ON public.seller_payouts (requested_at DESC)
  WHERE requested_at IS NOT NULL;

-- ────────────────────────────────────────────────────────────────
-- B2. Payout list + the seller's transfer destination
--     Recreated (not replaced) because columns are inserted in the middle.
-- ────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.v_seller_payout_summary;
CREATE VIEW public.v_seller_payout_summary
WITH (security_invoker = true) AS
SELECT
  sp.*,
  s.name AS store_name,
  s.owner_id,
  p.full_name    AS seller_name,
  p.phone        AS seller_phone,
  p.payout_method,
  p.payout_details,
  COALESCE(items.order_count, 0) AS order_count
FROM public.seller_payouts sp
JOIN public.stores s ON s.id = sp.store_id
LEFT JOIN public.profiles p ON p.id = s.owner_id
LEFT JOIN (
  SELECT payout_id, count(*)::int AS order_count
    FROM public.seller_payout_items
   GROUP BY payout_id
) items ON items.payout_id = sp.id;

COMMENT ON VIEW public.v_seller_payout_summary IS
  'Payout header joined to its store, its line count, and the seller''s payout destination. Filtered by the caller''s RLS on seller_payouts (security_invoker).';

-- Recreated views lose their grants; put SELECT back for signed-in callers.
GRANT SELECT ON public.v_seller_payout_summary TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- B3. request_my_payout() — the seller's "pay me now"
--
--     Scoping is structural, not cosmetic:
--       • no arguments at all — the store is derived from auth.uid(), so the
--         function has no way to address another seller's rows;
--       • only that store's orders, only reconciled ones, only unbatched ones;
--       • never sets status = 'paid' — mark_payout_paid() stays admin-only.
--     The split comes from seller_payout_amounts(), the same call the nightly
--     generator makes, so a requested batch and a generated one cannot differ.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_my_payout()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_store    uuid;
  v_date     date := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_bps      int;
  v_delivery numeric;
  v_payout   uuid;
  v_status   text;
  v_added    int := 0;
  v_net      numeric := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in to request a payout';
  END IF;

  SELECT id INTO v_store
    FROM public.stores
   WHERE owner_id = v_uid
   ORDER BY created_at
   LIMIT 1;
  IF v_store IS NULL THEN
    RAISE EXCEPTION 'No store is attached to this account';
  END IF;

  SELECT COALESCE(platform_fee_bps, 0), COALESCE(delivery_fee_amount, 0)
    INTO v_bps, v_delivery
    FROM public.platform_settings
   WHERE id = 1;
  v_bps := COALESCE(v_bps, 0);
  v_delivery := COALESCE(v_delivery, 0);

  -- Today's header already exists for this store?
  SELECT id, status INTO v_payout, v_status
    FROM public.seller_payouts
   WHERE store_id = v_store AND period_date = v_date;

  IF FOUND AND v_status = 'paid' THEN
    -- Money for today already went out; new orders must wait for the next
    -- batch rather than reopening a settled one.
    RAISE EXCEPTION
      'Today''s payout is already paid. Orders confirmed after that transfer go into the next batch.';
  ELSIF FOUND AND v_status <> 'draft' THEN
    -- A void batch is closed bookkeeping; appending lines to it would resurrect
    -- money nobody intends to send.
    RAISE EXCEPTION 'Today''s payout is % and cannot be changed', v_status;
  END IF;

  IF NOT FOUND THEN
    INSERT INTO public.seller_payouts
      (store_id, period_date, created_by, requested_at, requested_by)
    VALUES (v_store, v_date, v_uid, now(), v_uid)
    RETURNING id INTO v_payout;
  ELSE
    UPDATE public.seller_payouts
       SET requested_at = COALESCE(requested_at, now()),
           requested_by = COALESCE(requested_by, v_uid),
           updated_at   = now()
     WHERE id = v_payout;
  END IF;

  -- Attach this store's eligible orders, regardless of calendar day: a request
  -- means "pay me what you already confirmed", so orders that missed their
  -- nightly batch are swept in too. Same predicate as generate_daily_payouts,
  -- minus the day filter, plus the store scope.
  WITH eligible AS (
    SELECT o.id, m.net
      FROM public.orders o
      CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, v_bps, v_delivery) m
     WHERE o.store_id = v_store
       AND o.payment_status = 'paid'
       AND o.payment_method = 'gcash'
       AND o.source = 'online'
       AND o.funds_reconciled_at IS NOT NULL
       AND NOT o.payment_flagged
       AND o.status NOT IN ('cancelled', 'cancellation_requested')
       AND (o.total_amount - v_delivery) > 0
       AND NOT EXISTS (
         SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
       )
  )
  INSERT INTO public.seller_payout_items (payout_id, order_id, amount)
  SELECT v_payout, e.id, e.net
    FROM eligible e;

  GET DIAGNOSTICS v_added = ROW_COUNT;

  -- Recompute the header from its lines so a repeat request corrects the totals
  -- instead of adding them twice (same invariant as the nightly generator).
  UPDATE public.seller_payouts sp
     SET gross_amount  = COALESCE(t.gross, 0),
         delivery_fees = COALESCE(t.delivery, 0),
         platform_fee  = COALESCE(t.fee, 0),
         net_amount    = COALESCE(t.net, 0),
         updated_at    = now()
    FROM (
      SELECT i.payout_id,
             sum(o.total_amount)::numeric(12,2)     AS gross,
             (count(*) * v_delivery)::numeric(12,2) AS delivery,
             sum(m.commission)::numeric(12,2)       AS fee,
             sum(i.amount)::numeric(12,2)           AS net
        FROM public.seller_payout_items i
        JOIN public.orders o ON o.id = i.order_id
        CROSS JOIN LATERAL public.seller_payout_amounts(o.total_amount, v_bps, v_delivery) m
       WHERE i.payout_id = v_payout
       GROUP BY i.payout_id
    ) t
   WHERE sp.id = t.payout_id;

  SELECT net_amount INTO v_net FROM public.seller_payouts WHERE id = v_payout;

  RETURN jsonb_build_object(
    'payout_id',    v_payout,
    'period_date',  v_date,
    'orders_added', v_added,
    'net_amount',   COALESCE(v_net, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.request_my_payout() IS
  'Seller-initiated payout request: batches this caller''s already-reconciled, unbatched orders into today''s draft using seller_payout_amounts(). Never marks it paid.';

REVOKE EXECUTE ON FUNCTION public.request_my_payout() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.request_my_payout() TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 1. The calculation agrees with itself everywhere:
-- SELECT public.seller_payout_amounts(1000, 250, 100);   -- goods 900, fee 22.50, net 877.50
-- 2. The view and a generated batch must report the same numbers for the same
--    store/day. Compare v_seller_payables before and the draft after:
-- SELECT store_id, net_amount FROM public.v_seller_payables;
-- SELECT store_name, period_date, net_amount, platform_fee, order_count,
--        requested_at, seller_name, payout_method, payout_details
--   FROM public.v_seller_payout_summary ORDER BY period_date DESC LIMIT 5;
-- 3. A requested batch equals the sum of its own lines:
-- SELECT sp.id, sp.net_amount, sum(i.amount) AS lines
--   FROM public.seller_payouts sp
--   JOIN public.seller_payout_items i ON i.payout_id = sp.id
--  GROUP BY sp.id, sp.net_amount
-- HAVING sp.net_amount <> sum(i.amount);
-- 4. Security posture:
-- SELECT proname, prosecdef FROM pg_proc
--  WHERE proname IN ('seller_payout_amounts','generate_daily_payouts','request_my_payout');
