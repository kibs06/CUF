-- ══════════════════════════════════════════════════════════════════
-- PENDING LIVE MIGRATIONS — 2026-11-18 (project psczvbfoybqhjeqssimw)
--
-- Paste this whole file into the Supabase SQL Editor and run it once.
-- It is eight unapplied migrations, in version order, copied verbatim:
--
--   1/8  20261118051000  admins can read payment proofs (the queue said
--                        "no proof submitted" for orders that had one)
--   2/8  20261118060000  sellers can request a payout; one helper now owns
--                        the per-order payout maths
--   3/8  20261118070000  a proof's arrival time is stamped by the server
--                        and can never be moved
--   4/8  20261118080000  one GCash reference can only pay once, across
--                        orders, proofs and reservation deposits
--   5/8  20261118090000  a submitted proof deletes its own cart lines, in
--                        the same transaction as the order update
--   6/8  20261118100000  a retried cash checkout reuses one order instead
--                        of creating a second one (idempotency key)
--   7/8  20261118110000  one GCash proof file per minute per customer, so
--                        attempts cannot be filed back to back
--   8/8  20261118120000  the same window now covers bulk reservation
--                        deposits — one clock for both proof families
--
-- Section 1 is the file's PART 1 (the policy) only. Its PART 2 is a
-- read-only self-check that impersonates an admin and ends in ROLLBACK —
-- left out here so this file only applies. Run it separately afterwards if
-- you want the proof it prints.
--
-- Order matters: 5/8 redefines submit_gcash_proof from 20261118040000, 3/8
-- installs the trigger that RPC's insert runs under, and 4/8's guards must
-- exist before any proof is written carrying a reused reference. 6/8 is
-- independent of all of them — it only adds a nullable column and a partial
-- index on public.orders. 7/8 adds the proof window; 8/8 replaces BOTH
-- submit_gcash_proof and submit_bulk_reservation_deposit_proof and moves that
-- window into one shared helper, so it must follow 7/8 (the version it
-- extends), and no later file may copy the inline version instead.
--
-- Both apply paths were measured on a fresh local database, not argued:
-- `supabase db reset` replays the lineage from empty with all eight files in
-- this order (exit 0), and `supabase test db` is green afterwards.
-- ══════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────
-- 1/8  20261118051000_admin_read_payment_proofs   (PART 1 only)
-- ──────────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════════
-- Migration + self-check: Admin read access to manual-GCash payment proofs
-- Date: 2026-11-18
--
-- ONE PASTE. Part 1 applies the policy and COMMITS. Part 2 proves it and
-- ROLLS BACK, so the impersonation used to test RLS cannot outlive the run
-- and nothing in Part 2 can undo the apply.
--
-- WHY THIS EXISTS
--   The admin Payment verification queue reported "No proof submitted yet"
--   on orders whose proof demonstrably exists — including rows it was already
--   showing as "Verified — preparing", which cannot have been verified
--   without a proof.
--
--   The cause is RLS, not the query. The page embeds the proofs through
--   PostgREST (`orders → gcash_payment_proofs(...)`), and the policies from
--   20260808200000 cover only the order's customer and its store's seller.
--   RLS filters rows rather than raising: the embed comes back as `[]`, and
--   the page renders that as "nothing submitted". An admin could therefore
--   never read a reference, a sender or an amount — the three facts this
--   screen exists to check — nor open the receipt.
--
--   The screenshot layer is already covered: 20261118020000 §4 added
--   "Admins can read payment proofs" on storage.objects for this bucket, so
--   createSignedUrl works for an admin. Deliberate: this file adds nothing
--   there rather than ship a second policy that ORs with it and hides which
--   one is doing the work.
--
--   The gate is public.is_admin() — the same helper every other admin surface
--   uses (20260809120000, 20260810000000). It reads the role without
--   re-entering profiles RLS and excludes suspended accounts, so a suspended
--   admin loses the queue again immediately.
--
--   Read-only: no INSERT/UPDATE/DELETE is granted. Proofs stay written by the
--   SECURITY DEFINER submit RPC alone.
-- ══════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════
-- PART 1 — APPLY (committed)
-- ══════════════════════════════════════════════════════════════════
begin;

-- Idempotent: re-running replaces the policy rather than erroring.
DROP POLICY IF EXISTS "Admins can read all payment proofs"
  ON public.gcash_payment_proofs;
CREATE POLICY "Admins can read all payment proofs"
  ON public.gcash_payment_proofs FOR SELECT
  USING (public.is_admin());

COMMENT ON POLICY "Admins can read all payment proofs"
  ON public.gcash_payment_proofs IS
  'The admin verification queue embeds these rows. Without this policy the embed is filtered to [] and the queue reports "no proof submitted" for orders that have one.';

commit;


-- ──────────────────────────────────────────────────────────────────
-- 2/8  20261118060000_seller_payout_requests
-- ──────────────────────────────────────────────────────────────────
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


-- ──────────────────────────────────────────────────────────────────
-- 3/8  20261118070000_gcash_proof_server_time
-- ──────────────────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════
-- 20261118070000_gcash_proof_server_time.sql
--
-- Manual GCash proofs carry two clocks, and they are not the same thing:
--
--   • submitted_at — when the proof ARRIVED at the server. This is the one a
--     reviewer can trust: it is stamped by the database, never sent by the
--     app, and (from this file on) it cannot be moved afterwards by any
--     writer — not the customer, not a service_role script, not a replayed
--     call with a hand-made body.
--
--   • paid_at      — what the receipt CLAIMS. The app reads it off the
--     screenshot (OCR), so it describes an image the customer could have
--     edited. NULL means the receipt carried no readable clock. It is useful
--     evidence to compare against submitted_at, and never proof on its own.
--
--     submit_gcash_proof writes COALESCE(p_paid_at, now()) because the column
--     used to be treated as required. That fallback is a SERVER stamp, and a
--     reviewer reading it as "the receipt says …" would be reading our clock
--     as the customer's claim — the exact confusion this file exists to stop.
--     The trigger below therefore drops a paid_at that equals the transaction
--     clock: the fallback and the arrival stamp are then the same instant, and
--     a real receipt stamp (minute precision, from an earlier minute) never
--     is. The RPC is deliberately not rewritten for this: copying its 180-line
--     body into a new file to delete one COALESCE would put two definitions of
--     the submit path in the tree, and the one the database runs would be the
--     copy nobody edits.
--
-- Both are record-only: the customer's form shows neither, so there is
-- nothing on that screen to type over or to prompt an edit of the image.
--
-- Why a trigger and not just the column default:
--   `submitted_at` already exists (20260808200000) with DEFAULT now(), and the
--   submit RPC never passes it — but a DEFAULT is only a value for omitted
--   columns. Anyone who can write the row can name their own time. The BEFORE
--   trigger overwrites it on INSERT and pins it on UPDATE, which is what makes
--   "the proof arrived at 10:59" a fact about the server rather than a claim by
--   the sender.
--
-- Additive and idempotent: one trigger function, one trigger, comments. No
-- policy, grant or existing value changes. Re-running is safe.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. The column exists everywhere, and defaults to the server clock ──
ALTER TABLE public.gcash_payment_proofs
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

-- Legacy rows (if a database predates the default) get the migration moment,
-- never NULL: a proof without an arrival time is exactly the gap this closes.
UPDATE public.gcash_payment_proofs
   SET submitted_at = timezone('utc'::text, now())
 WHERE submitted_at IS NULL;

ALTER TABLE public.gcash_payment_proofs
  ALTER COLUMN submitted_at SET DEFAULT timezone('utc'::text, now());

ALTER TABLE public.gcash_payment_proofs
  ALTER COLUMN submitted_at SET NOT NULL;

-- ── 2. Pin it: server-stamped on insert, immutable on update ───────────
CREATE OR REPLACE FUNCTION public.pin_gcash_proof_time()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- The server's clock wins over whatever the statement supplied.
    NEW.submitted_at := timezone('utc'::text, now());

    -- An unreadable receipt must store NO claim, not our own stamp. The RPC's
    -- COALESCE fallback is exactly this transaction's clock, so it is
    -- indistinguishable from the arrival time written above — drop it. A real
    -- receipt stamp is minute-precision from an earlier minute and can never
    -- collide, and a client cannot know the transaction clock to fake one.
    IF NEW.paid_at IS NOT DISTINCT FROM now() THEN
      NEW.paid_at := NULL;
    END IF;
  ELSE
    -- The original arrival time is restored, so a proof cannot be backdated or
    -- forward-dated after the fact.
    NEW.submitted_at := OLD.submitted_at;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.pin_gcash_proof_time() IS
  'Server-owns the proof clocks: stamps submitted_at from the server clock on insert and pins it on update, and drops a paid_at equal to the transaction clock so an unreadable receipt stores no claim (NULL) instead of a server stamp.';

DROP TRIGGER IF EXISTS trg_pin_gcash_proof_time ON public.gcash_payment_proofs;
CREATE TRIGGER trg_pin_gcash_proof_time
  BEFORE INSERT OR UPDATE ON public.gcash_payment_proofs
  FOR EACH ROW
  EXECUTE FUNCTION public.pin_gcash_proof_time();

-- ── 3. Say out loud which clock is which ───────────────────────────────
COMMENT ON COLUMN public.gcash_payment_proofs.submitted_at IS
  'When the proof arrived at the server. Written by trg_pin_gcash_proof_time from the server clock on insert and immutable afterwards — the trusted anchor when a receipt''s own time is in question.';

COMMENT ON COLUMN public.gcash_payment_proofs.paid_at IS
  'What the receipt CLAIMS: read from the screenshot by the app''s OCR. NULL = the receipt carried no readable clock (the submit RPC''s now() fallback is stripped by trg_pin_gcash_proof_time, so this is never our own stamp). Customer-influenced — compare it with submitted_at, never rely on it alone.';

-- ── 2b. Rows written before this file ─────────────────────────────────
-- The fallback also landed on every existing row: paid_at was COALESCE'd to
-- the transaction clock, which is exactly where submitted_at came from. That
-- equality is the fingerprint of "we did not read a clock", so clear it. A
-- genuine receipt stamp sits at an earlier minute and is left alone.
UPDATE public.gcash_payment_proofs
   SET paid_at = NULL
 WHERE paid_at IS NOT NULL
   AND submitted_at IS NOT NULL
   AND paid_at = submitted_at;

COMMIT;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 1. The trigger is there, armed:
-- SELECT tgname, tgenabled FROM pg_trigger
--  WHERE tgrelid = 'public.gcash_payment_proofs'::regclass
--    AND NOT tgisinternal;
--
-- 2. A supplied arrival time is ignored (needs a real order + customer JWT,
--    so run it in the test harness rather than by hand):
--    INSERT ... submitted_at = '2020-01-01T00:00:00Z'  →  submitted_at = now()
--
-- 3. An arrival time cannot be moved:
-- UPDATE public.gcash_payment_proofs
--    SET submitted_at = '2020-01-01T00:00:00Z'
--  WHERE id = '<proof>';
-- SELECT submitted_at FROM public.gcash_payment_proofs WHERE id = '<proof>';
--   -- unchanged
--
-- 4. Nothing is NULL:
-- SELECT count(*) FROM public.gcash_payment_proofs WHERE submitted_at IS NULL;
--   -- 0
--
-- 5. No claim is a copy of its own arrival stamp:
-- SELECT count(*) FROM public.gcash_payment_proofs
--  WHERE paid_at IS NOT NULL AND paid_at = submitted_at;
--   -- 0
--
-- Rollback: DROP TRIGGER trg_pin_gcash_proof_time ON public.gcash_payment_proofs;
--           DROP FUNCTION public.pin_gcash_proof_time();
--           (the column, its default and its values are worth keeping)


-- ──────────────────────────────────────────────────────────────────
-- 4/8  20261118080000_gcash_reference_single_use
-- ──────────────────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════
-- 20261118080000_gcash_reference_single_use.sql
--
-- One GCash transfer must pay exactly once, anywhere in the product.
--
-- What already holds (checked before writing this file):
--   • gcash_payment_proofs.reference_number  is UNIQUE and digit-checked
--     (20260808200000) — the same reference cannot back two proofs.
--   • bulk_reservation_deposits.reference_number is UNIQUE and digit-checked
--     (20260913140000) — the same reference cannot back two deposits.
--   • orders.gcash_reference_number is UNIQUE only among PAID orders
--     (20260905000000, partial index) — the POS confirm path.
--
-- What did not hold: the three ledgers were never compared with each other.
-- So a customer could send ₱1,000 once and substantiate it twice —
--   order A's proof + reservation B's deposit,
--   order A's proof + a POS sale the seller rang up with that number,
--   a deposit  + a POS sale,
-- each of which is unique inside its own table and therefore passed every
-- check. That is duplication in the only sense that costs money.
--
-- This file adds one STABLE helper that answers "who already owns this
-- reference?" across all three, and a BEFORE trigger on each writer that
-- refuses the write when somebody else owns it:
--
--   gcash_payment_proofs      INSERT / UPDATE OF reference_number
--   orders                    INSERT / UPDATE OF gcash_reference_number
--   bulk_reservation_deposits INSERT / UPDATE OF reference_number
--
-- Deliberate properties:
--   • Same-owner rows are excluded (an order and its own proof are one
--     payment, not two; a deposit and its own reservation likewise), so the
--     legitimate pair is never rejected.
--   • Only 12–13 digit references are compared. PayMongo's legacy `pi_…`
--     ids live in orders.gcash_reference_number and mean something else;
--     normalising both sides to digits keeps them out of each other's way,
--     and lets a seller who types "4043 676 687260" still collide with the
--     stored "4043676687260".
--   • A refusal is a P0001 RAISE with a sentence a person can act on, which
--     the app already surfaces verbatim (DirectGcashService._toException).
--   • Nothing is repaired: existing cross-table duplicates, if any, are
--     reported by the query at the bottom of this file and left for a human
--     to refund or cancel. Deleting money evidence automatically is exactly
--     what a fix like this should not do.
--
-- Additive and idempotent: one function, one trigger function, three
-- triggers and one expression index. No backfill, no policy or grant change,
-- no column change.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Who already owns this reference? ────────────────────────────────
CREATE OR REPLACE FUNCTION public.gcash_reference_owner(
  p_ref            text,
  p_order_id       uuid DEFAULT NULL,
  p_reservation_id uuid DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner text;
BEGIN
  -- A paid or claimed order carrying the number in its own column. This is
  -- the POS path: the seller rang the sale up against that transfer.
  SELECT 'order ' || COALESCE(o.order_code, left(o.id::text, 8))
    INTO v_owner
    FROM public.orders o
   WHERE regexp_replace(COALESCE(o.gcash_reference_number, ''), '\D', '', 'g') = p_ref
     AND o.id IS DISTINCT FROM p_order_id
     AND (o.payment_status = 'paid' OR o.status = 'payment_under_review')
   LIMIT 1;
  IF v_owner IS NOT NULL THEN
    RETURN v_owner;
  END IF;

  -- A proof submitted for some other order (any status: a rejected attempt
  -- still names the transfer the customer says they made).
  SELECT 'order ' || COALESCE(o.order_code, left(o.id::text, 8))
    INTO v_owner
    FROM public.gcash_payment_proofs p
    JOIN public.orders o ON o.id = p.order_id
   WHERE p.reference_number = p_ref
     AND p.order_id IS DISTINCT FROM p_order_id
   LIMIT 1;
  IF v_owner IS NOT NULL THEN
    RETURN v_owner;
  END IF;

  -- A bulk-reservation deposit.
  SELECT 'reservation ' || left(d.reservation_id::text, 8)
    INTO v_owner
    FROM public.bulk_reservation_deposits d
   WHERE d.reference_number = p_ref
     AND d.reservation_id IS DISTINCT FROM p_reservation_id
   LIMIT 1;

  RETURN v_owner;
END;
$$;

COMMENT ON FUNCTION public.gcash_reference_owner(text, uuid, uuid) IS
  'Returns which order/reservation already owns a 12-13 digit GCash reference across proofs, paid-or-claimed orders and reservation deposits; NULL when the reference is free. Same-owner rows are excluded.';

-- ── 2. The guard every writer runs through ─────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_gcash_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row         jsonb := to_jsonb(NEW);
  v_raw         text;
  v_ref         text;
  v_order       uuid;
  v_reservation uuid;
  v_owner       text;
BEGIN
  v_raw := CASE TG_TABLE_NAME
             WHEN 'orders' THEN v_row ->> 'gcash_reference_number'
             ELSE v_row ->> 'reference_number'
           END;

  -- Digits only, so "4043 676 687260" and "4043676687260" are the same
  -- transfer. Anything that is not a 12-13 digit reference (a PayMongo
  -- pi_… id, an empty string, a mistyped short number) is not ours to judge.
  v_ref := regexp_replace(COALESCE(v_raw, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RETURN NEW;
  END IF;

  v_order := CASE TG_TABLE_NAME
               WHEN 'orders' THEN (v_row ->> 'id')::uuid
               WHEN 'gcash_payment_proofs' THEN (v_row ->> 'order_id')::uuid
             END;
  v_reservation := CASE TG_TABLE_NAME
                     WHEN 'bulk_reservation_deposits' THEN (v_row ->> 'reservation_id')::uuid
                   END;

  v_owner := public.gcash_reference_owner(v_ref, v_order, v_reservation);
  IF v_owner IS NOT NULL THEN
    RAISE EXCEPTION
      'That GCash reference number is already used for % — one transfer can only pay once.',
      v_owner;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_gcash_reference() IS
  'BEFORE INSERT/UPDATE guard on gcash_payment_proofs, orders and bulk_reservation_deposits: refuses a 12-13 digit GCash reference already owned by a different payment.';

DROP TRIGGER IF EXISTS trg_guard_gcash_reference ON public.gcash_payment_proofs;
CREATE TRIGGER trg_guard_gcash_reference
  BEFORE INSERT OR UPDATE OF reference_number ON public.gcash_payment_proofs
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

DROP TRIGGER IF EXISTS trg_guard_gcash_reference_orders ON public.orders;
CREATE TRIGGER trg_guard_gcash_reference_orders
  BEFORE INSERT OR UPDATE OF gcash_reference_number ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

DROP TRIGGER IF EXISTS trg_guard_gcash_reference_deposits ON public.bulk_reservation_deposits;
CREATE TRIGGER trg_guard_gcash_reference_deposits
  BEFORE INSERT OR UPDATE OF reference_number ON public.bulk_reservation_deposits
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

-- ── 3. Index the normalised reference on orders ─────────────────────────
-- The guard compares DIGITS, not the raw text (a seller may type "4043 676
-- 687260"), so the existing column index cannot serve that comparison and the
-- lookup would be a sequential scan of orders on every proof submission, every
-- POS confirm and every order insert. `regexp_replace(text,text,text,text)` is
-- IMMUTABLE, so the expression can be indexed; the proofs and deposits ledgers
-- already have a plain unique index on the exact column.
CREATE INDEX IF NOT EXISTS idx_orders_gcash_reference_digits
  ON public.orders (
    (regexp_replace(COALESCE(gcash_reference_number, ''), '\D', '', 'g'))
  );

COMMENT ON INDEX public.idx_orders_gcash_reference_digits IS
  'Digits-only form of orders.gcash_reference_number. Serves gcash_reference_owner(), which compares normalised references so a spaced entry collides with a stored one.';

COMMIT;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 0. The lookup index is there (and is used — see EXPLAIN in §5):
-- SELECT indexdef FROM pg_indexes
--  WHERE tablename = 'orders' AND indexname = 'idx_orders_gcash_reference_digits';
--
-- 1. The three guards are armed:
-- SELECT c.relname, t.tgname
--   FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
--  WHERE NOT t.tgisinternal
--    AND t.tgname LIKE 'trg_guard_gcash_reference%'
--  ORDER BY 1;
--   -- bulk_reservation_deposits | gcash_payment_proofs | orders
--
-- 2. A reference nobody owns is free:
-- SELECT public.gcash_reference_owner('999999999999');   -- NULL
--
-- 3. The same numbers in different formats are one number:
-- SELECT regexp_replace('4043 676 687260', '\D', '', 'g');  -- 4043676687260
--
-- 4. Cross-table duplicates that already exist (nothing is changed by this
--    file — this is the list to work through by hand):
-- SELECT 'order vs proof' AS kind, o.order_code, p.reference_number
--   FROM public.orders o
--   JOIN public.gcash_payment_proofs p
--     ON p.reference_number = regexp_replace(COALESCE(o.gcash_reference_number,''), '\D','','g')
--  WHERE o.id <> p.order_id
-- UNION ALL
-- SELECT 'proof vs deposit', NULL, p.reference_number
--   FROM public.gcash_payment_proofs p
--   JOIN public.bulk_reservation_deposits d ON d.reference_number = p.reference_number
-- UNION ALL
-- SELECT 'order vs deposit', o.order_code, d.reference_number
--   FROM public.orders o
--   JOIN public.bulk_reservation_deposits d
--     ON d.reference_number = regexp_replace(COALESCE(o.gcash_reference_number,''), '\D','','g');
--   -- expect 0 rows; any row is a real double-payment to resolve
--
-- Rollback: DROP TRIGGER trg_guard_gcash_reference ON public.gcash_payment_proofs;
--           DROP TRIGGER trg_guard_gcash_reference_orders ON public.orders;
--           DROP TRIGGER trg_guard_gcash_reference_deposits ON public.bulk_reservation_deposits;
--           DROP FUNCTION public.guard_gcash_reference();
--           DROP FUNCTION public.gcash_reference_owner(text, uuid, uuid);


-- ──────────────────────────────────────────────────────────────────
-- 5/8  20261118090000_cart_clears_on_proof
-- ──────────────────────────────────────────────────────────────────
-- ════════════════════════════════════════════════════════════════════
-- A submitted proof clears its own lines from the customer's cart
--
-- Until now the removal lived in the app: gcash_pay_screen.dart fetched the
-- order's items after a successful submit and edited the cart locally and on
-- the server. That made the cart correct only on the device that submitted —
-- every other device, and the same device after a kill, kept showing a
-- product the customer had already paid for.
--
-- A proof submission is the moment the money leaves the wallet, so the rows
-- that produced the order are removed here, inside the same transaction as
-- the order update. The client clear stays as a convenience for the screen
-- that is already open; it is no longer what makes the cart right.
--
-- Matching mirrors the client: product + size, quantity-aware. A cart line
-- holding exactly what was bought (or less) goes; a line holding more — the
-- customer re-added the same pair after paying — is reduced, not deleted.
--
-- Depends on: 20261118040000_manual_gcash_rpcs_v2.sql (the function replaced
-- here), 20261118070000 (the BEFORE INSERT proof-time trigger, untouched).
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. clear_purchased_cart_items(order, customer) → rows removed
--
--    Not callable by clients: it takes a customer id, so exposing it would
--    let anyone empty anyone's cart. Only the SECURITY DEFINER RPCs below
--    reach it.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.clear_purchased_cart_items(
  p_order_id  uuid,
  p_customer_id uuid
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line    record;
  v_removed int := 0;
BEGIN
  -- No null arguments to guard against: a NULL order or customer makes both
  -- joins empty, so the loop simply does not run.

  -- FOR UPDATE OF ci: the customer's own app may be touching these rows on
  -- another device, and the quantity arithmetic below must not read a value
  -- that changes before it writes.
  --
  -- Size: the cart line's own snapshot wins, the variant is the fallback, and
  -- a line with neither matches a sizeless order line — the same SKU either
  -- way. (cart_items.size exists on live databases; older local schemas only
  -- had the variant link, so both are read.) An order line WITH a size only
  -- ever matches a cart line of that same size, so a differently-sized pair in
  -- the cart survives.
  FOR v_line IN
    WITH bought AS (
      SELECT oi.product_id,
             COALESCE(oi.size, '') AS size,
             sum(oi.quantity)::int AS qty
        FROM public.order_items oi
       WHERE oi.order_id = p_order_id
         AND oi.product_id IS NOT NULL
       GROUP BY 1, 2
    )
    SELECT ci.id,
           ci.quantity AS have,
           (SELECT sum(b.qty)
              FROM bought b
             WHERE b.product_id = ci.product_id
               AND b.size = COALESCE(NULLIF(ci.size, ''), pv.size, '')
           ) AS bought
      FROM public.cart_items ci
      LEFT JOIN public.product_variants pv ON pv.id = ci.variant_id
     WHERE ci.user_id = p_customer_id
       FOR UPDATE OF ci
  LOOP
    CONTINUE WHEN v_line.bought IS NULL;             -- nothing of this in the order

    IF v_line.have <= v_line.bought THEN
      DELETE FROM public.cart_items WHERE id = v_line.id;
      v_removed := v_removed + 1;
    ELSE
      -- Keep what the customer still wants minus what the order already paid
      -- for: 3 in the cart, 1 bought → 2 left.
      UPDATE public.cart_items
         SET quantity = v_line.have - v_line.bought
       WHERE id = v_line.id;
    END IF;
  END LOOP;

  RETURN v_removed;
END;
$$;

COMMENT ON FUNCTION public.clear_purchased_cart_items(uuid, uuid) IS
  'Removes the cart lines an order paid for (quantity-aware). Called from the '
  'manual-GCash RPCs inside their own transaction; not exposed to clients.';

REVOKE ALL ON FUNCTION public.clear_purchased_cart_items(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- ────────────────────────────────────────────────────────────────
-- 2. submit_gcash_proof — body unchanged from 040000 except the cleanup
--    call after the order update. Kept as a full copy rather than a trigger
--    on gcash_payment_proofs so the deletion is visibly part of the same
--    transition that marks the order paid-looking.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_gcash_proof(
  p_order_id         uuid,
  p_reference_number text,
  p_sender_name      text,
  p_amount_paid      numeric,
  p_screenshot_url   text,
  p_screenshot_hash  text,
  p_paid_at          timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    text;
  v_store_id  uuid;
  v_customer  uuid;
  v_deadline  timestamptz;
  v_total     numeric;
  v_ref       text;
  v_sender    text;
  v_hash      text;
  v_attempt   int;
  v_short_id  text;
  v_code      text;
BEGIN
  SELECT status, store_id, customer_id, payment_confirmation_deadline,
         total_amount, order_code
    INTO v_status, v_store_id, v_customer, v_deadline, v_total, v_code
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_customer IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You can only submit proof for your own orders';
  END IF;
  IF v_status <> 'awaiting_payment_confirmation' THEN
    IF v_status = 'payment_under_review' THEN
      RAISE EXCEPTION 'Your proof is already with the store for review';
    END IF;
    RAISE EXCEPTION 'This order is no longer awaiting payment confirmation';
  END IF;
  IF v_deadline IS NOT NULL AND v_deadline < now() THEN
    RAISE EXCEPTION 'The payment window for this order has expired';
  END IF;

  IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
    RAISE EXCEPTION 'A payment screenshot is required';
  END IF;
  IF split_part(p_screenshot_url, '/', 1) <> p_order_id::text THEN
    RAISE EXCEPTION 'The screenshot does not match this order';
  END IF;

  v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RAISE EXCEPTION 'Enter a valid GCash reference number (12-13 digits)';
  END IF;

  v_sender := btrim(COALESCE(p_sender_name, ''));
  IF length(v_sender) < 2 THEN
    RAISE EXCEPTION 'Enter the GCash account name that sent the payment';
  END IF;

  IF p_amount_paid IS NULL OR abs(p_amount_paid - v_total) > 0.009 THEN
    RAISE EXCEPTION 'The amount you entered (₱%) does not match the order total (₱%). Send exactly ₱% and enter that amount.',
      COALESCE(to_char(p_amount_paid, 'FM999999990.00'), '0.00'),
      to_char(v_total, 'FM999999990.00'),
      to_char(v_total, 'FM999999990.00');
  END IF;

  v_hash := NULLIF(btrim(COALESCE(p_screenshot_hash, '')), '');
  IF v_hash IS NULL OR length(v_hash) < 32 THEN
    RAISE EXCEPTION 'The screenshot could not be verified. Please attach the image again.';
  END IF;

  SELECT count(*) + 1 INTO v_attempt
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id;
  IF v_attempt > 3 THEN
    RAISE EXCEPTION 'You have used all 3 payment attempts for this order';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs
     WHERE order_id = p_order_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'A proof is already awaiting review';
  END IF;

  BEGIN
    INSERT INTO public.gcash_payment_proofs (
      order_id, reference_number, screenshot_url, submitted_by,
      sender_name, amount_paid, paid_at, screenshot_hash, attempt_no, status
    ) VALUES (
      p_order_id, v_ref, p_screenshot_url, auth.uid(),
      v_sender, p_amount_paid, COALESCE(p_paid_at, now()), v_hash,
      v_attempt, 'pending'
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE reference_number = v_ref AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That GCash reference number has already been used for another order';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE screenshot_hash = v_hash AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That screenshot has already been used for another order. Attach this payment''s own receipt.';
    END IF;
    RAISE EXCEPTION 'This payment could not be recorded. Please try again.';
  END;

  -- Paid-looking order: stop the pay-window clock, start the review SLA.
  UPDATE public.orders
     SET status = 'payment_under_review',
         review_deadline = now() + interval '24 hours'
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation';

  -- The purchase is complete, so its lines leave the cart here, in this same
  -- transaction: the cart is right on every device, not just the one that
  -- submitted. Wrapped like the admin bell below — a cart quirk must never
  -- reject a real payment, and the client's own clear still covers the case
  -- where this is skipped.
  BEGIN
    PERFORM public.clear_purchased_cart_items(p_order_id, v_customer);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'cart cleanup failed for order %: %', p_order_id, SQLERRM;
  END;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (
    p_order_id,
    CASE WHEN v_attempt = 1 THEN 'proof_submitted' ELSE 'resubmitted' END,
    auth.uid(),
    'Attempt ' || v_attempt || ' — reference ' || v_ref ||
      ', ₱' || to_char(p_amount_paid, 'FM999999990.00') ||
      ' from ' || v_sender
  );

  v_short_id := left(p_order_id::text, 8);

  -- Seller bell (guarded: orders.store_id is nullable).
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications
      (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id, 'new_order',
      'Payment awaiting verification',
      'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
        ' (code ' || COALESCE(v_code, '—') || '). Verify the reference, name and amount.',
      p_order_id
    );
  END IF;

  -- Admin bell: the money lands in the platform account, so the admin must
  -- see every proof even before the seller acts.
  --
  -- Wrapped: a notification must never be able to reject a REAL payment. If
  -- the admin_notifications type CHECK is behind (or a future migration
  -- changes it), the proof still lands and the seller bell still rings.
  BEGIN
  INSERT INTO public.admin_notifications (user_id, type, title, body, reference_id, metadata)
  SELECT p.id,
         'payment_proof_submitted',
         'GCash proof submitted',
         'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
           ' from ' || v_sender || ' (ref ' || v_ref || ', code ' || COALESCE(v_code, '—') || ')',
         p_order_id,
         jsonb_build_object(
           'order_id', p_order_id,
           'reference_number', v_ref,
           'amount_paid', p_amount_paid,
           'attempt_no', v_attempt,
           'store_id', v_store_id
         )
    FROM public.profiles p
   WHERE p.role = 'admin'
     AND NOT COALESCE(p.suspended, false);
  EXCEPTION WHEN others THEN
    NULL;  -- best-effort: never fail a submitted payment over a bell
  END;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'payment_under_review',
    'attempt_no', v_attempt
  );
END;
$$;

-- No grant statements: CREATE OR REPLACE keeps the privileges 20261118040000
-- set on this exact signature, and a fresh database applies that file first.


-- ──────────────────────────────────────────────────────────────────
-- 6/8  20261118100000_cash_order_idempotency
-- ──────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- Cash / COD orders: one submission, one order.
--
-- Placing a cash order is a plain client INSERT into public.orders, so a
-- submit that timed out after the row landed was indistinguishable from a
-- submit that never arrived: the customer retried and got a second order,
-- stock and all. Nothing on the row identified the attempt.
--
-- The app now sends a key it keeps for the life of one checkout screen
-- (rotated once an order exists), and this index makes a second insert with
-- that key impossible. The client reads the 23505 as "the first attempt
-- succeeded" and opens the order it already has instead of writing another.
--
-- GCash is untouched: its checkout goes through create_gcash_checkout and is
-- already capped by uq_orders_one_awaiting_payment_confirmation_per_customer,
-- which allows one open awaiting-payment order per customer. Cash orders are
-- status 'pending', so the two guards never overlap.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS idempotency_key text;

COMMENT ON COLUMN public.orders.idempotency_key IS
  'Client-generated key for one checkout submission. A retried submit reuses it, so an insert that timed out after it landed cannot become a second order. NULL on POS and GCash orders and on rows written before this column existed.';

-- 8–64 characters: a UUID today, open enough to swap identifier later without
-- another migration, and bounded so a client cannot park text on the row.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_idempotency_key_len;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_idempotency_key_len
  CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 8 AND 64);

-- Partial, like every other guard on this table: POS rows, GCash rows and the
-- whole pre-change history carry no key, and NULLs must not collide.
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_customer_idempotency_key
  ON public.orders (customer_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMENT ON INDEX public.uq_orders_customer_idempotency_key IS
  'One order per (customer, checkout key). A retried submit after a timeout hits this index and the app answers with the order the first attempt created.';


-- ──────────────────────────────────────────────────────────────────
-- 7/8  20261118110000_gcash_proof_cooldown

-- ════════════════════════════════════════════════════════════════════
-- One GCash proof file per minute, per customer
--
-- The uniqueness indexes already stop the harmful duplicates: the same
-- reference, the same screenshot, one pending proof per order, one attempt
-- number per order. They say nothing about a customer who files attempt
-- after attempt with fresh material — each one becomes a seller notification,
-- an admin bell, an order_payment_events row and a review somebody has to
-- read. That is persistence, not duplication, and no index can refuse it.
--
-- So the RPC carries a cooldown: if this customer filed any proof within the
-- last 60 seconds, the submission is refused before a row is written and the
-- message says how long is left. The clock is submitted_at, which
-- trg_pin_gcash_proof_time stamps from the server and pins on update, so a
-- client cannot wait out its own cooldown by editing the row.
--
-- 60 seconds is deliberately short: the proof goes to a human for review, so
-- a real customer has no reason to file twice inside a minute, while a legit
-- correction after a mistyped reference costs one minute, not a lockout.
-- Follows the existing attempt rules rather than replacing them — the 3-attempt
-- cap and the one-pending-proof index still decide how many attempts an order
-- may have.
--
-- The window is a platform setting, not a constant in the function, because the
-- right number belongs to the operator (a busy store may want 30s) and because
-- the suites that are about OTHER rules file several proofs in a row and would
-- otherwise be testing this clock instead of their own subject. 0 disables it.
--
-- Depends on: 20261118090000 (the function replaced here, which added the cart
-- cleanup call) and 20261118070000 (the proof-time trigger). Body otherwise
-- identical to 20261118090000; signature unchanged, so the grants set by
-- 20261118040000 still apply.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE public.platform_settings
  ADD COLUMN IF NOT EXISTS gcash_proof_cooldown_seconds int NOT NULL DEFAULT 60;

ALTER TABLE public.platform_settings
  DROP CONSTRAINT IF EXISTS platform_settings_gcash_proof_cooldown_check;
ALTER TABLE public.platform_settings
  ADD CONSTRAINT platform_settings_gcash_proof_cooldown_check
  CHECK (gcash_proof_cooldown_seconds BETWEEN 0 AND 3600);

COMMENT ON COLUMN public.platform_settings.gcash_proof_cooldown_seconds IS
  'Minimum seconds between two GCash proof files from the same customer. 0 disables the cooldown. Enforced inside submit_gcash_proof against the server-stamped submitted_at, so it cannot be waited out from the client.';

CREATE OR REPLACE FUNCTION public.submit_gcash_proof(
  p_order_id         uuid,
  p_reference_number text,
  p_sender_name      text,
  p_amount_paid      numeric,
  p_screenshot_url   text,
  p_screenshot_hash  text,
  p_paid_at          timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_default_cooldown constant int := 60;
  v_status    text;
  v_store_id  uuid;
  v_customer  uuid;
  v_deadline  timestamptz;
  v_total     numeric;
  v_ref       text;
  v_sender    text;
  v_hash      text;
  v_attempt   int;
  v_short_id  text;
  v_code      text;
  v_last_file timestamptz;
  v_wait      int;
  v_cooldown  int;
BEGIN
  SELECT status, store_id, customer_id, payment_confirmation_deadline,
         total_amount, order_code
    INTO v_status, v_store_id, v_customer, v_deadline, v_total, v_code
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_customer IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You can only submit proof for your own orders';
  END IF;
  IF v_status <> 'awaiting_payment_confirmation' THEN
    IF v_status = 'payment_under_review' THEN
      RAISE EXCEPTION 'Your proof is already with the store for review';
    END IF;
    RAISE EXCEPTION 'This order is no longer awaiting payment confirmation';
  END IF;
  IF v_deadline IS NOT NULL AND v_deadline < now() THEN
    RAISE EXCEPTION 'The payment window for this order has expired';
  END IF;

  -- ── Per-customer cooldown ────────────────────────────────────────
  -- Checked after the order's own state, so a customer who already filed for
  -- THIS order is told that (a more useful sentence) rather than the clock.
  -- Across every order the customer owns: filing for a second order is still
  -- filing, and the seller and admin bells ring the same way.
  SELECT COALESCE(max(s.gcash_proof_cooldown_seconds), c_default_cooldown)
    INTO v_cooldown
    FROM public.platform_settings s
   WHERE s.id = 1;

  IF COALESCE(v_cooldown, c_default_cooldown) > 0 THEN
    v_cooldown := COALESCE(v_cooldown, c_default_cooldown);
    SELECT max(pr.submitted_at) INTO v_last_file
      FROM public.gcash_payment_proofs pr
      JOIN public.orders o ON o.id = pr.order_id
     WHERE o.customer_id = v_customer;

    IF v_last_file IS NOT NULL
       AND v_last_file > now() - make_interval(secs => v_cooldown) THEN
      v_wait := GREATEST(
        1,
        CEIL(EXTRACT(EPOCH FROM
          (v_last_file + make_interval(secs => v_cooldown) - now())))::int
      );
      RAISE EXCEPTION 'You just filed a GCash proof. Try again in % second(s).',
        v_wait;
    END IF;
  END IF;

  IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
    RAISE EXCEPTION 'A payment screenshot is required';
  END IF;
  IF split_part(p_screenshot_url, '/', 1) <> p_order_id::text THEN
    RAISE EXCEPTION 'The screenshot does not match this order';
  END IF;

  v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RAISE EXCEPTION 'Enter a valid GCash reference number (12-13 digits)';
  END IF;

  v_sender := btrim(COALESCE(p_sender_name, ''));
  IF length(v_sender) < 2 THEN
    RAISE EXCEPTION 'Enter the GCash account name that sent the payment';
  END IF;

  IF p_amount_paid IS NULL OR abs(p_amount_paid - v_total) > 0.009 THEN
    RAISE EXCEPTION 'The amount you entered (₱%) does not match the order total (₱%). Send exactly ₱% and enter that amount.',
      COALESCE(to_char(p_amount_paid, 'FM999999990.00'), '0.00'),
      to_char(v_total, 'FM999999990.00'),
      to_char(v_total, 'FM999999990.00');
  END IF;

  v_hash := NULLIF(btrim(COALESCE(p_screenshot_hash, '')), '');
  IF v_hash IS NULL OR length(v_hash) < 32 THEN
    RAISE EXCEPTION 'The screenshot could not be verified. Please attach the image again.';
  END IF;

  SELECT count(*) + 1 INTO v_attempt
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id;
  IF v_attempt > 3 THEN
    RAISE EXCEPTION 'You have used all 3 payment attempts for this order';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs
     WHERE order_id = p_order_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'A proof is already awaiting review';
  END IF;

  BEGIN
    INSERT INTO public.gcash_payment_proofs (
      order_id, reference_number, screenshot_url, submitted_by,
      sender_name, amount_paid, paid_at, screenshot_hash, attempt_no, status
    ) VALUES (
      p_order_id, v_ref, p_screenshot_url, auth.uid(),
      v_sender, p_amount_paid, COALESCE(p_paid_at, now()), v_hash,
      v_attempt, 'pending'
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE reference_number = v_ref AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That GCash reference number has already been used for another order';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE screenshot_hash = v_hash AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That screenshot has already been used for another order. Attach this payment''s own receipt.';
    END IF;
    RAISE EXCEPTION 'This payment could not be recorded. Please try again.';
  END;

  -- Paid-looking order: stop the pay-window clock, start the review SLA.
  UPDATE public.orders
     SET status = 'payment_under_review',
         review_deadline = now() + interval '24 hours'
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation';

  -- The purchase is complete, so its lines leave the cart here, in this same
  -- transaction: the cart is right on every device, not just the one that
  -- submitted. Wrapped like the admin bell below — a cart quirk must never
  -- reject a real payment, and the client's own clear still covers the case
  -- where this is skipped.
  BEGIN
    PERFORM public.clear_purchased_cart_items(p_order_id, v_customer);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'cart cleanup failed for order %: %', p_order_id, SQLERRM;
  END;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (
    p_order_id,
    CASE WHEN v_attempt = 1 THEN 'proof_submitted' ELSE 'resubmitted' END,
    auth.uid(),
    'Attempt ' || v_attempt || ' — reference ' || v_ref ||
      ', ₱' || to_char(p_amount_paid, 'FM999999990.00') ||
      ' from ' || v_sender
  );

  v_short_id := left(p_order_id::text, 8);

  -- Seller bell (guarded: orders.store_id is nullable).
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications
      (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id, 'new_order',
      'Payment awaiting verification',
      'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
        ' (code ' || COALESCE(v_code, '—') || '). Verify the reference, name and amount.',
      p_order_id
    );
  END IF;

  -- Admin bell: the money lands in the platform account, so the admin must
  -- see every proof even before the seller acts.
  --
  -- Wrapped: a notification must never be able to reject a REAL payment. If
  -- the admin_notifications type CHECK is behind (or a future migration
  -- changes it), the proof still lands and the seller bell still rings.
  BEGIN
  INSERT INTO public.admin_notifications (user_id, type, title, body, reference_id, metadata)
  SELECT p.id,
         'payment_proof_submitted',
         'GCash proof submitted',
         'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
           ' from ' || v_sender || ' (ref ' || v_ref || ', code ' || COALESCE(v_code, '—') || ')',
         p_order_id,
         jsonb_build_object(
           'order_id', p_order_id,
           'reference_number', v_ref,
           'amount_paid', p_amount_paid,
           'attempt_no', v_attempt,
           'store_id', v_store_id
         )
    FROM public.profiles p
   WHERE p.role = 'admin'
     AND NOT COALESCE(p.suspended, false);
  EXCEPTION WHEN others THEN
    NULL;  -- best-effort: never fail a submitted payment over a bell
  END;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'payment_under_review',
    'attempt_no', v_attempt
  );
END;
$$;

-- No grant statements: CREATE OR REPLACE keeps the privileges 20261118040000
-- set on this exact signature, and a fresh database applies that file first.

-- ──────────────────────────────────────────────────────────────────
-- 8/8  20261118120000_bulk_deposit_proof_cooldown
-- ──────────────────────────────────────────────────────────────────

-- ════════════════════════════════════════════════════════════════════
-- One GCash proof file per minute — now across both proof families
--
-- 20261118110000 put the cooldown in submit_gcash_proof. The bulk
-- reservation deposit RPC, submit_bulk_reservation_deposit_proof, has the
-- same shape and the same hole: its unique indexes stop a reused reference
-- and a second proof for one reservation, and nothing stops a customer
-- filing attempts for reservation after reservation with fresh material.
--
-- Rather than grow a second copy of the same rule (two clocks that can drift,
-- and a customer who can alternate between families to double their rate),
-- the window now lives in one helper, public.gcash_proof_cooldown_remaining(),
-- which reads the newest file of EITHER kind for that customer. Both RPCs call
-- it. It takes a customer id, so it is not a client RPC.
--
-- Unchanged on purpose:
--   • the window still comes from platform_settings.gcash_proof_cooldown_seconds
--     (default 60, 0 disables, admin-only write);
--   • the clock is still the server's submitted_at, which nothing client-side
--     can move (order proofs are pinned by trg_pin_gcash_proof_time; deposits
--     are stamped by the column default inside the RPC, which never accepts a
--     client time);
--   • each RPC keeps its own error voice — the order flow raises a sentence
--     with the seconds left, the deposit flow raises the short code
--     'PROOF_COOLDOWN' that lib/services/reservation_service.dart already
--     translates for the customer;
--   • every other rule in both functions is byte-identical to the versions
--     they replace (20261118110000 and 20260913140000).
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. The one rule: seconds left before this customer may file again
--    (0 = may file now).
--
--    Not callable by clients: it takes a customer id, so exposing it would
--    let anyone probe another customer's activity timing.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gcash_proof_cooldown_remaining(
  p_customer uuid
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_default_cooldown constant int := 60;
  v_cooldown int;
  v_last     timestamptz;
BEGIN
  IF p_customer IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(s.gcash_proof_cooldown_seconds, c_default_cooldown)
    INTO v_cooldown
    FROM public.platform_settings s
   WHERE s.id = 1;

  v_cooldown := COALESCE(v_cooldown, c_default_cooldown);
  IF v_cooldown <= 0 THEN
    RETURN 0;
  END IF;

  -- The newest file of either kind. GREATEST ignores NULLs, which is what we
  -- want: a customer with only order proofs, or only deposits, still works.
  SELECT GREATEST(
           (SELECT max(pr.submitted_at)
              FROM public.gcash_payment_proofs pr
              JOIN public.orders o ON o.id = pr.order_id
             WHERE o.customer_id = p_customer),
           (SELECT max(d.submitted_at)
              FROM public.bulk_reservation_deposits d
             WHERE d.submitted_by = p_customer)
         )
    INTO v_last;

  IF v_last IS NULL OR v_last <= now() - make_interval(secs => v_cooldown) THEN
    RETURN 0;
  END IF;

  RETURN GREATEST(
    1,
    CEIL(EXTRACT(EPOCH FROM
      (v_last + make_interval(secs => v_cooldown) - now())))::int
  );
END;
$$;

COMMENT ON FUNCTION public.gcash_proof_cooldown_remaining(uuid) IS
  'Seconds a customer must still wait before filing another GCash proof — order proof or bulk reservation deposit, whichever they filed last. 0 means they may file now. The window comes from platform_settings.gcash_proof_cooldown_seconds and the clock from the server-stamped submitted_at.';

REVOKE ALL ON FUNCTION public.gcash_proof_cooldown_remaining(uuid)
  FROM PUBLIC, anon, authenticated;

-- ────────────────────────────────────────────────────────────────
-- 2. submit_gcash_proof — the inline window from 20261118110000 replaced by
--    the shared helper, so it now also respects a deposit filed a moment ago.
--    Everything else is unchanged.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_gcash_proof(
  p_order_id         uuid,
  p_reference_number text,
  p_sender_name      text,
  p_amount_paid      numeric,
  p_screenshot_url   text,
  p_screenshot_hash  text,
  p_paid_at          timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    text;
  v_store_id  uuid;
  v_customer  uuid;
  v_deadline  timestamptz;
  v_total     numeric;
  v_ref       text;
  v_sender    text;
  v_hash      text;
  v_attempt   int;
  v_short_id  text;
  v_code      text;
  v_wait      int;
BEGIN
  SELECT status, store_id, customer_id, payment_confirmation_deadline,
         total_amount, order_code
    INTO v_status, v_store_id, v_customer, v_deadline, v_total, v_code
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_customer IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You can only submit proof for your own orders';
  END IF;
  IF v_status <> 'awaiting_payment_confirmation' THEN
    IF v_status = 'payment_under_review' THEN
      RAISE EXCEPTION 'Your proof is already with the store for review';
    END IF;
    RAISE EXCEPTION 'This order is no longer awaiting payment confirmation';
  END IF;
  IF v_deadline IS NOT NULL AND v_deadline < now() THEN
    RAISE EXCEPTION 'The payment window for this order has expired';
  END IF;

  -- Per-customer cooldown, shared with the bulk deposit flow.
  v_wait := public.gcash_proof_cooldown_remaining(v_customer);
  IF v_wait > 0 THEN
    RAISE EXCEPTION 'You just filed a GCash proof. Try again in % second(s).',
      v_wait;
  END IF;

  IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
    RAISE EXCEPTION 'A payment screenshot is required';
  END IF;
  IF split_part(p_screenshot_url, '/', 1) <> p_order_id::text THEN
    RAISE EXCEPTION 'The screenshot does not match this order';
  END IF;

  v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RAISE EXCEPTION 'Enter a valid GCash reference number (12-13 digits)';
  END IF;

  v_sender := btrim(COALESCE(p_sender_name, ''));
  IF length(v_sender) < 2 THEN
    RAISE EXCEPTION 'Enter the GCash account name that sent the payment';
  END IF;

  IF p_amount_paid IS NULL OR abs(p_amount_paid - v_total) > 0.009 THEN
    RAISE EXCEPTION 'The amount you entered (₱%) does not match the order total (₱%). Send exactly ₱% and enter that amount.',
      COALESCE(to_char(p_amount_paid, 'FM999999990.00'), '0.00'),
      to_char(v_total, 'FM999999990.00'),
      to_char(v_total, 'FM999999990.00');
  END IF;

  v_hash := NULLIF(btrim(COALESCE(p_screenshot_hash, '')), '');
  IF v_hash IS NULL OR length(v_hash) < 32 THEN
    RAISE EXCEPTION 'The screenshot could not be verified. Please attach the image again.';
  END IF;

  SELECT count(*) + 1 INTO v_attempt
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id;
  IF v_attempt > 3 THEN
    RAISE EXCEPTION 'You have used all 3 payment attempts for this order';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs
     WHERE order_id = p_order_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'A proof is already awaiting review';
  END IF;

  BEGIN
    INSERT INTO public.gcash_payment_proofs (
      order_id, reference_number, screenshot_url, submitted_by,
      sender_name, amount_paid, paid_at, screenshot_hash, attempt_no, status
    ) VALUES (
      p_order_id, v_ref, p_screenshot_url, auth.uid(),
      v_sender, p_amount_paid, COALESCE(p_paid_at, now()), v_hash,
      v_attempt, 'pending'
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE reference_number = v_ref AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That GCash reference number has already been used for another order';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.gcash_payment_proofs
       WHERE screenshot_hash = v_hash AND order_id <> p_order_id
    ) THEN
      RAISE EXCEPTION 'That screenshot has already been used for another order. Attach this payment''s own receipt.';
    END IF;
    RAISE EXCEPTION 'This payment could not be recorded. Please try again.';
  END;

  -- Paid-looking order: stop the pay-window clock, start the review SLA.
  UPDATE public.orders
     SET status = 'payment_under_review',
         review_deadline = now() + interval '24 hours'
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation';

  -- The purchase is complete, so its lines leave the cart here, in this same
  -- transaction: the cart is right on every device, not just the one that
  -- submitted. Wrapped like the admin bell below — a cart quirk must never
  -- reject a real payment, and the client's own clear still covers the case
  -- where this is skipped.
  BEGIN
    PERFORM public.clear_purchased_cart_items(p_order_id, v_customer);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'cart cleanup failed for order %: %', p_order_id, SQLERRM;
  END;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (
    p_order_id,
    CASE WHEN v_attempt = 1 THEN 'proof_submitted' ELSE 'resubmitted' END,
    auth.uid(),
    'Attempt ' || v_attempt || ' — reference ' || v_ref ||
      ', ₱' || to_char(p_amount_paid, 'FM999999990.00') ||
      ' from ' || v_sender
  );

  v_short_id := left(p_order_id::text, 8);

  -- Seller bell (guarded: orders.store_id is nullable).
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications
      (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id, 'new_order',
      'Payment awaiting verification',
      'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
        ' (code ' || COALESCE(v_code, '—') || '). Verify the reference, name and amount.',
      p_order_id
    );
  END IF;

  -- Admin bell: the money lands in the platform account, so the admin must
  -- see every proof even before the seller acts.
  --
  -- Wrapped: a notification must never be able to reject a REAL payment. If
  -- the admin_notifications type CHECK is behind (or a future migration
  -- changes it), the proof still lands and the seller bell still rings.
  BEGIN
  INSERT INTO public.admin_notifications (user_id, type, title, body, reference_id, metadata)
  SELECT p.id,
         'payment_proof_submitted',
         'GCash proof submitted',
         'Order #' || v_short_id || ' — ₱' || to_char(v_total, 'FM999999990.00') ||
           ' from ' || v_sender || ' (ref ' || v_ref || ', code ' || COALESCE(v_code, '—') || ')',
         p_order_id,
         jsonb_build_object(
           'order_id', p_order_id,
           'reference_number', v_ref,
           'amount_paid', p_amount_paid,
           'attempt_no', v_attempt,
           'store_id', v_store_id
         )
    FROM public.profiles p
   WHERE p.role = 'admin'
     AND NOT COALESCE(p.suspended, false);
  EXCEPTION WHEN others THEN
    NULL;  -- best-effort: never fail a submitted payment over a bell
  END;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'payment_under_review',
    'attempt_no', v_attempt
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 3. submit_bulk_reservation_deposit_proof — cooldown added after the
--    reservation's own state and deadline, before anything is written.
--    Raises the short code the app already translates. Every other rule
--    (ownership, status, deadline, folder, 12–13 digits, cross-family
--    reference dedupe, one-proof-per-reservation, seller notification) is
--    copied unchanged from 20260913140000.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_bulk_reservation_deposit_proof(
    p_reservation_id   UUID,
    p_reference_number TEXT,
    p_screenshot_url   TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_customer UUID := auth.uid();
    v_store_owner UUID;
    v_ref TEXT;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize vs confirm/reject/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'awaiting_deposit' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;
    IF v_reservation.deposit_deadline IS NOT NULL
       AND v_reservation.deposit_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'DEPOSIT_DEADLINE_PASSED';
    END IF;

    -- Per-customer cooldown, shared with the order proof flow. A short code
    -- rather than a sentence because this RPC's errors are translated by
    -- friendlyReservationError() in lib/services/reservation_service.dart.
    IF public.gcash_proof_cooldown_remaining(v_customer) > 0 THEN
        RAISE EXCEPTION 'PROOF_COOLDOWN';
    END IF;

    IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;
    -- The screenshot must live in THIS reservation's folder
    -- ({reservation_id}/{file}) — same anti-mixing rule as order proofs.
    IF split_part(p_screenshot_url, '/', 1) <> p_reservation_id::text THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;

    -- Normalize to digits-only; GCash refs are 13 digits (12 tolerated —
    -- matches lib/utils/gcash_ref_extractor and the order-flow rule).
    v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
    IF length(v_ref) NOT IN (12, 13) THEN
        RAISE EXCEPTION 'INVALID_PROOF_REFERENCE';
    END IF;

    -- Platform-wide dedupe ACROSS proof families: a reference already
    -- used for an order proof cannot confirm a deposit too. (The reverse
    -- direction — the dormant order flow checking deposits — is not
    -- added; the order flow is legacy and out of scope here.) Guarded on
    -- to_regclass so the migration is safe even where the dormant
    -- order-proof table was never created.
    IF to_regclass('public.gcash_payment_proofs') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.gcash_payment_proofs
                   WHERE reference_number = v_ref) THEN
            RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.bulk_reservation_deposits
            (reservation_id, reference_number, screenshot_url, submitted_by)
        VALUES (p_reservation_id, v_ref, p_screenshot_url, v_customer);
    EXCEPTION WHEN unique_violation THEN
        -- Distinguish the concurrent double-submit race (reservation_id
        -- UNIQUE) from a genuinely reused reference (platform UNIQUE).
        IF EXISTS (SELECT 1 FROM public.bulk_reservation_deposits
                   WHERE reservation_id = p_reservation_id) THEN
            RAISE EXCEPTION 'DEPOSIT_ALREADY_SUBMITTED';
        END IF;
        RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
    END;

    -- Notify the seller that a proof awaits verification.
    SELECT s.owner_id INTO v_store_owner
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    IF v_store_owner IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_store_owner, 'reservations',
            'Deposit proof submitted',
            'A customer submitted a GCash deposit proof (₱' ||
            COALESCE(v_reservation.deposit_amount, 0)::int || ', ref ' ||
            v_ref || ') for their ' || v_reservation.quantity ||
            '-unit reservation. Verify it in your GCash app and confirm to hold the stock.'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_bulk_reservation_deposit_proof FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_bulk_reservation_deposit_proof TO authenticated;
