-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller payouts (end-of-day remittance)
-- Date: 2026-11-18
-- Depends on: 20261118020000 (platform account + settings),
--             20261118030000 (v2 columns), 20261118040000 (RPCs)
--
-- The platform receives every online GCash payment and owes each store its
-- share. This migration makes that debt explicit and auditable:
--
--   seller_payouts      one row per store per Manila business day
--   seller_payout_items one row per ORDER inside a payout (amount = the
--                       net that order contributes)
--
-- Net math (per order):
--   goods      = total_amount − delivery_fee_amount   (delivery is the
--                platform's pass-through to the courier, never seller money)
--   commission = round(goods × platform_fee_bps / 10000, 2)   (default 0)
--   net        = total_amount − delivery_fee_amount − commission
--
-- Eligibility (all required): paid, online GCash, admin-reconciled
-- (funds_reconciled_at set), not flagged, not cancelled, not already in a
-- payout. That is the two-person control: a seller-verified order only
-- becomes payable once an admin confirms the money exists.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. seller_payouts
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_payouts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id       UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  period_date    DATE NOT NULL,
  gross_amount   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (gross_amount >= 0),
  delivery_fees  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fees >= 0),
  platform_fee   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (platform_fee >= 0),
  net_amount     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (net_amount >= 0),
  status         TEXT NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft', 'paid', 'void')),
  paid_at        TIMESTAMPTZ,
  paid_reference TEXT,
  receipt_path   TEXT,
  notes          TEXT,
  created_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_seller_payouts_store_day UNIQUE (store_id, period_date)
);

CREATE INDEX IF NOT EXISTS idx_seller_payouts_period
  ON public.seller_payouts (period_date DESC, status);

CREATE INDEX IF NOT EXISTS idx_seller_payouts_store
  ON public.seller_payouts (store_id, period_date DESC);

COMMENT ON TABLE public.seller_payouts IS
  'End-of-day remittance to a store. One row per (store, Manila business day). Drafts are generated from reconciled orders; paid requires a transfer reference and receipt.';

-- ────────────────────────────────────────────────────────────────
-- 2. seller_payout_items — the per-order breakdown
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_payout_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id  UUID NOT NULL REFERENCES public.seller_payouts(id) ON DELETE CASCADE,
  order_id   UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  amount     NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_seller_payout_items_order UNIQUE (order_id)
);

CREATE INDEX IF NOT EXISTS idx_seller_payout_items_payout
  ON public.seller_payout_items (payout_id);

COMMENT ON COLUMN public.seller_payout_items.amount IS
  'This order''s contribution to the payout: total − delivery fee − platform commission.';
COMMENT ON TABLE public.seller_payout_items IS
  'Per-order lines of a payout. UNIQUE(order_id) is what makes an order payable exactly once, even if generate_daily_payouts is re-run.';

-- ────────────────────────────────────────────────────────────────
-- 3. RLS — seller reads own, admin reads all, nobody writes directly
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_payout_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sellers can read their own payouts" ON public.seller_payouts;
CREATE POLICY "Sellers can read their own payouts"
  ON public.seller_payouts FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.stores s
       WHERE s.id = seller_payouts.store_id AND s.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins can read all payouts" ON public.seller_payouts;
CREATE POLICY "Admins can read all payouts"
  ON public.seller_payouts FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "Sellers can read their own payout items" ON public.seller_payout_items;
CREATE POLICY "Sellers can read their own payout items"
  ON public.seller_payout_items FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.seller_payouts sp
        JOIN public.stores s ON s.id = sp.store_id
       WHERE sp.id = seller_payout_items.payout_id
         AND s.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins can read all payout items" ON public.seller_payout_items;
CREATE POLICY "Admins can read all payout items"
  ON public.seller_payout_items FOR SELECT
  USING (public.is_admin());

-- No INSERT/UPDATE/DELETE policies: only the SECURITY DEFINER RPCs write.

-- ────────────────────────────────────────────────────────────────
-- 4. Views
-- ────────────────────────────────────────────────────────────────

-- What each store is owed for orders that are reconciled but not yet in a
-- payout. This is the admin's "generate today's payouts" source of truth.
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
  sum(round((o.total_amount - cfg.delivery) * cfg.bps / 10000.0, 2))::numeric(12,2)
    AS platform_fee,
  sum(
    o.total_amount - cfg.delivery
      - round((o.total_amount - cfg.delivery) * cfg.bps / 10000.0, 2)
  )::numeric(12,2) AS net_amount
FROM public.orders o
JOIN public.stores s ON s.id = o.store_id
CROSS JOIN cfg
WHERE o.payment_status = 'paid'
  AND o.payment_method = 'gcash'
  AND o.source = 'online'
  AND o.funds_reconciled_at IS NOT NULL
  AND NOT o.payment_flagged
  AND o.status NOT IN ('cancelled', 'cancellation_requested')
  AND NOT EXISTS (
    SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
  )
GROUP BY o.store_id, s.name, s.owner_id;

COMMENT ON VIEW public.v_seller_payables IS
  'Reconciled, paid, unbatched online-GCash orders grouped by store — the amounts the platform still owes.';

-- Payout list with its line count, for the admin and seller screens.
DROP VIEW IF EXISTS public.v_seller_payout_summary;
CREATE VIEW public.v_seller_payout_summary
WITH (security_invoker = true) AS
SELECT
  sp.*,
  s.name AS store_name,
  s.owner_id,
  COALESCE(items.order_count, 0) AS order_count
FROM public.seller_payouts sp
JOIN public.stores s ON s.id = sp.store_id
LEFT JOIN (
  SELECT payout_id, count(*)::int AS order_count
    FROM public.seller_payout_items
   GROUP BY payout_id
) items ON items.payout_id = sp.id;

COMMENT ON VIEW public.v_seller_payout_summary IS
  'Payout header joined to its store and line count. Filtered by the caller''s RLS on seller_payouts (security_invoker).';

-- ────────────────────────────────────────────────────────────────
-- 5. generate_daily_payouts(p_date) — idempotent draft generation
--    Safe to run repeatedly: the header is unique per (store, day) and
--    each order may appear in exactly one payout item.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_daily_payouts(p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date       date := COALESCE(p_date, (now() AT TIME ZONE 'Asia/Manila')::date);
  v_bps        int;
  v_delivery   numeric;
  v_headers    int := 0;
  v_items      int := 0;
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

  -- 5a. Draft headers for every store with eligible orders that day.
  WITH eligible AS (
    SELECT o.id,
           o.store_id,
           o.total_amount,
           o.total_amount - v_delivery AS goods,
           round((o.total_amount - v_delivery) * v_bps / 10000.0, 2) AS commission
      FROM public.orders o
     WHERE o.payment_status = 'paid'
       AND o.payment_method = 'gcash'
       AND o.source = 'online'
       AND o.funds_reconciled_at IS NOT NULL
       AND NOT o.payment_flagged
       AND o.status NOT IN ('cancelled', 'cancellation_requested')
       AND (o.created_at AT TIME ZONE 'Asia/Manila')::date = v_date
       AND NOT EXISTS (
         SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
       )
  ),
  agg AS (
    SELECT store_id,
           sum(total_amount)::numeric(12,2)                 AS gross,
           (count(*) * v_delivery)::numeric(12,2)           AS delivery_total,
           sum(commission)::numeric(12,2)                   AS fee,
           sum(total_amount - v_delivery - commission)::numeric(12,2) AS net
      FROM eligible
     GROUP BY store_id
  )
  INSERT INTO public.seller_payouts
    (store_id, period_date, gross_amount, delivery_fees, platform_fee, net_amount, created_by)
  SELECT store_id, v_date, gross, delivery_total, fee, net, auth.uid()
    FROM agg
  ON CONFLICT (store_id, period_date) DO NOTHING;

  GET DIAGNOSTICS v_headers = ROW_COUNT;

  -- 5b. Attach the orders to their store's draft payout for that day.
  WITH eligible AS (
    SELECT o.id,
           o.store_id,
           o.total_amount,
           round((o.total_amount - v_delivery) * v_bps / 10000.0, 2) AS commission
      FROM public.orders o
     WHERE o.payment_status = 'paid'
       AND o.payment_method = 'gcash'
       AND o.source = 'online'
       AND o.funds_reconciled_at IS NOT NULL
       AND NOT o.payment_flagged
       AND o.status NOT IN ('cancelled', 'cancellation_requested')
       AND (o.created_at AT TIME ZONE 'Asia/Manila')::date = v_date
       AND NOT EXISTS (
         SELECT 1 FROM public.seller_payout_items i WHERE i.order_id = o.id
       )
  )
  INSERT INTO public.seller_payout_items (payout_id, order_id, amount)
  SELECT sp.id, e.id, (e.total_amount - v_delivery - e.commission)
    FROM eligible e
    JOIN public.seller_payouts sp
      ON sp.store_id = e.store_id
     AND sp.period_date = v_date
     AND sp.status = 'draft'
  ON CONFLICT (order_id) DO NOTHING;

  GET DIAGNOSTICS v_items = ROW_COUNT;

  -- 5c. Recompute every draft header for the day from its items, so a
  -- re-run that adds orders corrects the totals instead of drifting.
  UPDATE public.seller_payouts sp
     SET gross_amount  = COALESCE(t.gross, 0),
         delivery_fees = COALESCE(t.delivery, 0),
         platform_fee  = COALESCE(t.fee, 0),
         net_amount    = COALESCE(t.net, 0),
         updated_at    = now()
    FROM (
      SELECT i.payout_id,
             sum(o.total_amount)::numeric(12,2) AS gross,
             (count(*) * v_delivery)::numeric(12,2) AS delivery,
             sum(round((o.total_amount - v_delivery) * v_bps / 10000.0, 2))::numeric(12,2) AS fee,
             sum(
               i.amount
             )::numeric(12,2) AS net
        FROM public.seller_payout_items i
        JOIN public.orders o ON o.id = i.order_id
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
-- 6. mark_payout_paid — the admin's record of the actual transfer
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_payout_paid(
  p_payout_id  uuid,
  p_reference  text,
  p_receipt    text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status   text;
  v_ref      text;
  v_paid_ref text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can mark a payout paid';
  END IF;

  v_ref := btrim(COALESCE(p_reference, ''));
  IF length(v_ref) < 4 THEN
    RAISE EXCEPTION 'Enter the GCash/bank reference of the transfer';
  END IF;

  SELECT status, paid_reference INTO v_status, v_paid_ref
    FROM public.seller_payouts WHERE id = p_payout_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payout not found';
  END IF;

  -- Idempotent replay: reporting the SAME transfer twice (the portal retried a
  -- request that had already landed) must not error and must not rewrite the
  -- audit trail. A DIFFERENT reference on an already-paid payout is refused,
  -- because that would silently overwrite which transfer settled the money.
  IF v_status = 'paid' THEN
    IF v_paid_ref IS DISTINCT FROM v_ref THEN
      RAISE EXCEPTION 'This payout is already marked paid with reference %',
        COALESCE(v_paid_ref, '(none)');
    END IF;
    RETURN jsonb_build_object(
      'payout_id', p_payout_id,
      'status', 'paid',
      'idempotent', true
    );
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft payouts can be marked paid';
  END IF;

  UPDATE public.seller_payouts
     SET status = 'paid',
         paid_at = now(),
         paid_reference = v_ref,
         receipt_path = NULLIF(btrim(COALESCE(p_receipt, '')), ''),
         updated_at = now()
   WHERE id = p_payout_id;

  RETURN jsonb_build_object('payout_id', p_payout_id, 'status', 'paid');
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 7. Grants
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.generate_daily_payouts(date) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.generate_daily_payouts(date) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.mark_payout_paid(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.mark_payout_paid(uuid, text, text) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 8. Private bucket for payout receipts (transfer screenshots/PDFs)
--    Admin-only in both directions: a seller may READ their own payout
--    row, but the receipt object itself is internal bookkeeping.
-- ────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('payout-receipts', 'payout-receipts', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Admins can upload payout receipts" ON storage.objects;
CREATE POLICY "Admins can upload payout receipts"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'payout-receipts' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can read payout receipts" ON storage.objects;
CREATE POLICY "Admins can read payout receipts"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'payout-receipts' AND public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 9. Device gate on the money tables
--    Payouts are seller money, the same class as orders: readable only
--    from a trusted device (admins bypass inside the policy). The
--    installer sweeps every RLS table in public, so this covers the two
--    tables added here and re-asserts the policy on the existing ones.
--    Not exempted in device_gate_exempt_tables(), by design.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM public.install_device_gate_policies();
EXCEPTION
  WHEN undefined_function THEN
    RAISE EXCEPTION
      'install_device_gate_policies() is missing: seller_payouts would ship ungated';
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT * FROM public.v_seller_payables LIMIT 5;
-- SELECT proname, prosecdef FROM pg_proc
--  WHERE proname IN ('generate_daily_payouts','mark_payout_paid');
