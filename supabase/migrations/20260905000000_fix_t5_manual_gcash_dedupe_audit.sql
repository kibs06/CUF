-- ══════════════════════════════════════════════════════════════════
-- Migration: T5 — manual GCash fraud surface hardening
-- Date: 2026-09-05
--
-- Purpose: close Threat T5 (payment fraud / unauthorized payment
-- activity) on the manual gateway-free GCash flows. Three controls:
--
--   1. REF DEDUPE (POS flow). The in-person POS flow
--      (lib/screens/seller/pos_screen.dart) lets the seller type the
--      customer's GCash reference number when confirming payment
--      (orders.gcash_reference_number, source='pos'). Nothing today
--      stops the same reference number from being reused on a second
--      paid order. Real GCash reference numbers are globally unique
--      per transaction, so a reference that already confirmed one
--      paid order can never legitimately confirm another. Enforced
--      with a partial unique index on paid orders (DB-level, cannot
--      be bypassed by calling the API directly), plus a friendly
--      error mapped in the app.
--
--   2. AMOUNT + AUDIT (both flows). A new admin-only audit table
--      records every seller confirm/reject decision with the
--      reference number and the order amount shown to the seller at
--      decision time (captured server-side, never client-reported).
--      Written by:
--        • a trigger on orders for the POS flow (the seller's
--          "Payment Received" UPDATE is a plain client write — a
--          trigger is the only way to audit it server-side), and
--        • the confirm/reject RPCs for the dormant direct flow
--          (same transaction as the state change).
--      The value is retrospective pattern detection (high rejection
--      rates, suspicious reference patterns) — this is NOT an
--      alerting system.
--
--   3. CLOSE THE REMOTE ROUTE. The attempt-#5 gateway-free RPCs
--      (create_gcash_checkout / submit_gcash_proof / confirm_ /
--      reject_gcash_payment) were formally deprecated on 2026-08-09
--      (revive_paymongo migration) but their EXECUTE grants were
--      never revoked, so any authenticated user can still create an
--      ONLINE (source='online') awaiting_payment_confirmation order
--      via PostgREST and feed the seller's confirmation queue from
--      anywhere. No wired UI calls create_gcash_checkout anymore
--      (checkout uses PayMongo). This migration revokes EXECUTE on
--      create_gcash_checkout — the order-CREATION entry point — so no
--      NEW manual orders can be created at all. submit/confirm/
--      reject/expire stay granted so any legacy awaiting orders
--      (created while attempt #5 was live, Aug 8–9) can still be
--      resolved by their customer/seller.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. POS reference-number dedupe
--    Rule: a reference number may appear on at most ONE paid order.
--    payment_status='paid' = "money moved" (POS confirms flip
--    pending → paid in the same UPDATE that writes the reference).
--    Empty/NULL references are exempt (the POS flow treats the
--    reference as optional) and pending/cancelled rows are exempt
--    (a cancelled POS order is deleted outright, so its reference
--    becomes reusable again — see §1b).
--
-- 1a. Pre-clean: the live DB may already hold duplicate references
--     on paid orders (the exact reuse attack). The unique index
--     cannot be created until duplicates are resolved. Keep the
--     EARLIEST row per reference (the genuine first use) and NULL
--     the later ones. Only touches paid rows that actually carry a
--     duplicate reference; nothing else is modified.
-- ────────────────────────────────────────────────────────────────
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY gcash_reference_number
           ORDER BY created_at, id
         ) AS rn
  FROM public.orders
  WHERE payment_status = 'paid'
    AND gcash_reference_number IS NOT NULL
    AND gcash_reference_number <> ''
) UPDATE public.orders o
   SET gcash_reference_number = NULL
  FROM ranked r
 WHERE o.id = r.id
   AND r.rn > 1;

-- 1b. The constraint itself.
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_gcash_reference_number_paid
  ON public.orders(gcash_reference_number)
  WHERE payment_status = 'paid' AND gcash_reference_number <> '';

COMMENT ON INDEX public.uq_orders_gcash_reference_number_paid IS
  'T5 dedupe: a GCash reference number may be used on at most ONE paid order. Rejects the reference-reuse attack on the POS manual flow (and any other writer). Partial: only paid orders with a non-empty reference are constrained, so cancelled/pending rows and optional-empty references are unaffected. A cancelled POS order is deleted outright, which frees its reference for reuse.';

-- ────────────────────────────────────────────────────────────────
-- 2. gcash_payment_decision_audit — admin-only decision trail
--    One row per seller confirm/reject decision on a manual GCash
--    submission. amount_shown_to_seller is the order total captured
--    at decision time (from the server-side state change, never a
--    client-reported value). source distinguishes the mechanism:
--    'pos'   = in-person POS static-QR flow (seller's Payment
--              Received tap, audited by the trigger in §3)
--    'queue' = dormant direct flow's confirm/reject RPCs (§4)
--    order_id / seller_id use ON DELETE SET NULL so the audit row
--    survives order deletion (customers may delete cancelled orders)
--    and account deletion — the trail is for retrospective analysis.
--
--    Access model (mirrors seller_application_audit_log, T3):
--      • SELECT — admins only (RLS policy using public.is_admin()).
--      • INSERT/UPDATE/DELETE — no RLS policy for any client role,
--        and table grants explicitly revoked from anon,
--        authenticated AND service_role. The only writers are the
--        SECURITY DEFINER trigger (§3) and the SECURITY DEFINER RPCs
--        (§4), which run as the table owner and bypass RLS/grants.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gcash_payment_decision_audit (
  id                     BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  order_id               UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  seller_id              UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reference_number       TEXT,
  amount_shown_to_seller NUMERIC(12,2),
  decision               TEXT NOT NULL CHECK (decision IN ('confirmed', 'rejected')),
  source                 TEXT NOT NULL DEFAULT 'pos' CHECK (source IN ('pos', 'queue')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gcash_payment_decision_audit_order
  ON public.gcash_payment_decision_audit(order_id);

CREATE INDEX IF NOT EXISTS idx_gcash_payment_decision_audit_seller
  ON public.gcash_payment_decision_audit(seller_id, created_at DESC);

-- Retrospective pattern detection: "this reference pattern looks
-- suspicious across multiple stores" / "unusually high rejection rate".
CREATE INDEX IF NOT EXISTS idx_gcash_payment_decision_audit_ref
  ON public.gcash_payment_decision_audit(reference_number);

COMMENT ON TABLE public.gcash_payment_decision_audit IS
  'T5: append-only audit of every seller confirm/reject decision on manual (gateway-free) GCash payments. amount_shown_to_seller captured at decision time server-side. Written ONLY by the POS audit trigger (log_pos_gcash_confirm_audit) and the confirm/reject RPCs — no client role can write it. Purpose: retrospective pattern detection, not alerting.';

ALTER TABLE public.gcash_payment_decision_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read GCash decision audit"
  ON public.gcash_payment_decision_audit;
CREATE POLICY "Admins can read GCash decision audit"
  ON public.gcash_payment_decision_audit FOR SELECT
  USING (public.is_admin());

-- Belt-and-suspenders at the grant level (the base schema's ALTER
-- DEFAULT PRIVILEGES grants ALL on new tables to anon / authenticated
-- / service_role, so REVOKE FROM PUBLIC alone would NOT strip those).
REVOKE ALL ON public.gcash_payment_decision_audit FROM PUBLIC;
REVOKE ALL ON public.gcash_payment_decision_audit FROM anon, authenticated, service_role;
GRANT  SELECT ON public.gcash_payment_decision_audit TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 3. POS confirm audit trigger
--    The POS "Payment Received" action is a plain client UPDATE on
--    orders (pos_screen.dart _confirmGcashPayment) — no RPC to hook
--    into. This trigger is the only way to capture that decision
--    server-side, and a trigger cannot be bypassed by calling the
--    API directly.
--
--    Fires when payment_status or gcash_reference_number changes,
--    and logs only genuine POS manual GCash confirms:
--      source='pos' + payment_method='gcash' + payment_status='paid'
--      (and the order was NOT already paid — INSERT covers any
--      future path that creates a POS order paid-at-insert).
--    Excluded automatically:
--      • online PayMongo orders (source='online') — the webhook's
--        paid UPDATE never fires this branch.
--      • the dormant queue flow (source='online') — its RPCs audit
--        themselves with source='queue' in §4.
--    seller_id = auth.uid() at the moment of the seller's UPDATE.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_pos_gcash_confirm_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source = 'pos'
     AND NEW.payment_method = 'gcash'
     AND NEW.payment_status = 'paid'
     AND (TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
    INSERT INTO public.gcash_payment_decision_audit
      (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
    VALUES (
      NEW.id,
      auth.uid(),
      NULLIF(NEW.gcash_reference_number, ''),
      NEW.total_amount,
      'confirmed',
      'pos'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_pos_gcash_confirm_audit ON public.orders;
CREATE TRIGGER trg_log_pos_gcash_confirm_audit
  AFTER INSERT OR UPDATE OF payment_status, gcash_reference_number ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.log_pos_gcash_confirm_audit();

COMMENT ON FUNCTION public.log_pos_gcash_confirm_audit IS
  'T5: AFTER INSERT/UPDATE OF payment_status ON orders — appends one immutable row to gcash_payment_decision_audit for every POS (source=''pos'', method=''gcash'') manual GCash confirm. SECURITY DEFINER so the insert bypasses RLS/grants; the trigger is one of exactly two write paths to the audit table.';

-- ────────────────────────────────────────────────────────────────
-- 4. Dormant direct flow — audit the seller's confirm/reject RPCs
--    CREATE OR REPLACE (migrations are immutable; the originals live
--    in 20260808210000). Same signatures and behavior, PLUS an
--    append to gcash_payment_decision_audit inside the same
--    transaction, with the proof's reference number and the order's
--    total captured at decision time. Grants on the functions are
--    untouched by CREATE OR REPLACE.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_gcash_payment(
  p_order_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id    uuid;
  v_customer_id uuid;
  v_total       numeric;
  v_ref         text;
  v_updated     int;
  v_short_id    text;
BEGIN
  SELECT s.owner_id, o.customer_id, o.total_amount
    INTO v_owner_id, v_customer_id, v_total
    FROM public.orders o
    JOIN public.stores s ON s.id = o.store_id
   WHERE o.id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_owner_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the store owner can confirm this payment';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'The customer has not submitted proof of payment yet';
  END IF;

  UPDATE public.orders
     SET status = 'pending',
         payment_status = 'paid',
         payment_verified_at = now()
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'This order is no longer awaiting confirmation (already confirmed, rejected, or expired)';
  END IF;

  -- T5 audit — same transaction as the state change, server-side only.
  SELECT reference_number INTO v_ref
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'confirmed', auth.uid(), 'Payment confirmed by seller');

  INSERT INTO public.gcash_payment_decision_audit
    (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
  VALUES (p_order_id, auth.uid(), v_ref, v_total, 'confirmed', 'queue');

  -- Customer in-app notification.
  v_short_id := left(p_order_id::text, 8);
  INSERT INTO public.notifications (user_id, order_id, category, title, message)
  VALUES (v_customer_id, p_order_id, 'processing',
          'Payment confirmed',
          'Order #' || v_short_id || ' — payment received. The store will start preparing your order.');

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'pending',
    'payment_status', 'paid'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_gcash_payment(
  p_order_id uuid,
  p_reason   text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id  uuid;
  v_total     numeric;
  v_ref       text;
  v_cancelled boolean;
BEGIN
  SELECT s.owner_id, o.total_amount
    INTO v_owner_id, v_total
    FROM public.orders o
    JOIN public.stores s ON s.id = o.store_id
   WHERE o.id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_owner_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the store owner can reject this payment';
  END IF;

  v_cancelled := public.cancel_awaiting_gcash_order(
    p_order_id,
    'Payment rejected by seller',
    COALESCE(NULLIF(p_reason, ''), 'No reason provided'),
    'rejected',
    auth.uid(),
    true
  );
  IF NOT v_cancelled THEN
    RAISE EXCEPTION 'This order is no longer awaiting confirmation';
  END IF;

  -- T5 audit — same transaction as the state change, server-side only.
  SELECT reference_number INTO v_ref
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id;

  INSERT INTO public.gcash_payment_decision_audit
    (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
  VALUES (p_order_id, auth.uid(), v_ref, v_total, 'rejected', 'queue');

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'cancelled');
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 5. Close the remote route: no NEW manual orders can be created
--    The other four RPCs stay granted (legacy awaiting orders must
--    still be resolvable); only the creation entry point is revoked.
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) FROM authenticated;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run after applying)
-- ────────────────────────────────────────────────────────────────
-- -- Dedupe constraint exists
-- SELECT indexname FROM pg_indexes
--   WHERE tablename = 'orders' AND indexname = 'uq_orders_gcash_reference_number_paid';
--
-- -- Dedupe behaves: second paid order with an existing reference is rejected
-- -- (run as a POS-style UPDATE; expect unique_violation 23505)
-- UPDATE public.orders SET payment_status='paid', gcash_reference_number='<ref>'
--  WHERE id = '<order1>';   -- ok
-- UPDATE public.orders SET payment_status='paid', gcash_reference_number='<ref>'
--  WHERE id = '<order2>';   -- ERROR: duplicate key value violates unique constraint ...
--
-- -- Audit table + RLS
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='gcash_payment_decision_audit';
--
-- SELECT polname FROM pg_policy
--   WHERE polrelid = 'public.gcash_payment_decision_audit'::regclass;
--
-- -- POS confirm writes an audit row (trigger):
-- UPDATE public.orders SET payment_status='paid', gcash_reference_number='1234567890123'
--  WHERE id = '<pos_gcash_order>';
-- SELECT decision, source, reference_number, amount_shown_to_seller
--   FROM public.gcash_payment_decision_audit WHERE order_id = '<pos_gcash_order>';
--
-- -- create_gcash_checkout no longer callable by authenticated:
-- SELECT has_function_privilege('authenticated',
--   'public.create_gcash_checkout(jsonb, text, jsonb)', 'EXECUTE');  -- expect false