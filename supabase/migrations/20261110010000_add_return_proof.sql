-- ══════════════════════════════════════════════════════════════════
-- Migration: return photo proof (customer → seller)
-- Date: 2026-11-10
--
-- The return sheet lets the customer attach one photo (defect, wrong item,
-- worn sole…) so the seller can judge the request without a chat round-trip.
--
-- What this adds:
--   • orders.return_proof_path TEXT — storage PATH (not a public URL; the
--     bucket below is private, same convention as payment-proofs)
--   • private `return-proofs` bucket, path `{order_id}/{uuid}.jpg` — the
--     FIRST folder segment is the order id so policies can join to orders
--   • request_my_return() gains p_proof_path (optional, stored as-is)
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Column ─────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_proof_path TEXT;

COMMENT ON COLUMN public.orders.return_proof_path IS
  'Storage path in the private return-proofs bucket ({order_id}/{uuid}.jpg); shown to the seller via signed URL';

-- ── 2. Private bucket + policies (mirrors payment-proofs) ─────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('return-proofs', 'return-proofs', false)
ON CONFLICT (id) DO NOTHING;

-- INSERT — the order's customer uploads into their own order's folder.
DROP POLICY IF EXISTS "Customers can upload return proofs to their own order" ON storage.objects;
CREATE POLICY "Customers can upload return proofs to their own order"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'return-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

-- SELECT — the order's customer OR the seller of the order's store.
DROP POLICY IF EXISTS "Order customers and sellers can read return proofs" ON storage.objects;
CREATE POLICY "Order customers and sellers can read return proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'return-proofs'
    AND (
      (storage.foldername(name))[1] IN (
        SELECT o.id::text FROM public.orders o
        WHERE o.customer_id = auth.uid()
      )
      OR (storage.foldername(name))[1] IN (
        SELECT o.id::text FROM public.orders o
        JOIN public.stores s ON s.id = o.store_id
        WHERE s.owner_id = auth.uid()
      )
    )
  );

-- UPDATE / DELETE — the customer may replace/remove before the request is
-- decided; the row itself is locked to the RPC + seller update paths.
DROP POLICY IF EXISTS "Customers can replace their own return proof images" ON storage.objects;
CREATE POLICY "Customers can replace their own return proof images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'return-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Customers can delete their own return proof images" ON storage.objects;
CREATE POLICY "Customers can delete their own return proof images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'return-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

-- ── 3. RPC: accept + store the proof path ─────────────────────────
-- The 3-arg overload from 20261110000000 is dropped so PostgREST/Supabase
-- RPC routing has exactly one candidate.
DROP FUNCTION IF EXISTS public.request_my_return(uuid, text, text);

CREATE OR REPLACE FUNCTION public.request_my_return(
  p_order_id uuid,
  p_reason   text,
  p_details  text DEFAULT NULL,
  p_proof_path text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_store_id uuid;
  v_since timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Choose a reason for returning this order'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_reason = 'Other' AND (p_details IS NULL OR btrim(p_details) = '') THEN
    RAISE EXCEPTION 'Tell us a little more, so the maker knows what happened'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  IF v_order.id IS NULL OR v_order.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Order not found'
      USING ERRCODE = '42501';
  END IF;

  IF v_order.status = 'return_requested' THEN
    RAISE EXCEPTION 'You have already asked to return this order — the maker will respond shortly.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.status = 'refunded' THEN
    RAISE EXCEPTION 'This order has already been refunded.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.status NOT IN ('delivered', 'received') THEN
    RAISE EXCEPTION 'Only delivered orders can be returned. Contact the store for help with this order.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.payment_status IS DISTINCT FROM 'paid' THEN
    RAISE EXCEPTION 'Only paid orders can be returned.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Delivery moment: prefer the real history rows; fall back to created_at
  -- for rows predating the history trigger.
  SELECT max(changed_at) INTO v_since
    FROM public.order_status_history
   WHERE order_id = p_order_id
     AND status IN ('delivered', 'received');

  IF v_since IS NULL THEN
    v_since := v_order.created_at;
  END IF;

  IF v_since IS NOT NULL AND v_since < now() - interval '7 days' THEN
    RAISE EXCEPTION 'The 7-day return window for this order has closed. Message the store and they may still help.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
     SET status = 'return_requested',
         return_reason = p_reason,
         return_details = nullif(btrim(coalesce(p_details, '')), ''),
         return_requested_at = now(),
         return_proof_path = nullif(btrim(coalesce(p_proof_path, '')), '')
   WHERE id = p_order_id;

  -- Customer feed (category 'returns' already exists for this).
  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_order.customer_id,
      p_order_id,
      'returns',
      'Return requested',
      'Order #' || left(p_order_id::text, 8) || ' — waiting for the maker to confirm your return. Reason: ' || p_reason
    );
  END IF;

  -- Seller bell (store-scoped; the channel the seller app reads).
  -- NULL store_id (custom/legacy orders) would 23502-abort the whole
  -- request, so read it into a guarded variable first (repo recipient rule).
  v_store_id := v_order.store_id;
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id,
      'return_request',
      'Return requested',
      'Order #' || left(p_order_id::text, 8) || ' — ' || p_reason,
      p_order_id
    );
  END IF;

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'return_requested');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_my_return(uuid, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_my_return(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.request_my_return(uuid, text, text, text) IS
  'Customer return request. delivered/received + paid + within 7 days of delivery. Own orders only. Optional photo proof path stored for the seller. Writes customer + seller notifications in the same transaction.';
