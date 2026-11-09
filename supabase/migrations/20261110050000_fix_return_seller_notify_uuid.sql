-- ══════════════════════════════════════════════════════════════════
-- Fix: request_my_return aborted on seller-notification insert
-- Date: 2026-11-10
--
-- `seller_notifications.reference_id` is UUID, but the return RPC passed
-- `p_order_id::text` → 42804, aborting the whole transaction (the order
-- update rolled back with it). Every other notifier passes the UUID
-- directly (see submit_gcash_proof, model_request) — this aligns.
--
-- Full final function (proof set mandatory 1-4, cash-aware gate).
-- ══════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.request_my_return(uuid, text, text);
DROP FUNCTION IF EXISTS public.request_my_return(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.request_my_return(
  p_order_id uuid,
  p_reason   text,
  p_details  text DEFAULT NULL,
  p_proof_path text DEFAULT NULL,
  p_proof_paths TEXT[] DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_since timestamptz;
  v_proofs TEXT[] := '{}';
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

  -- Photo proof is mandatory: accept the new array param, falling back to
  -- the legacy single path for older app builds still sending it.
  IF p_proof_paths IS NOT NULL AND array_length(p_proof_paths, 1) IS NOT NULL THEN
    v_proofs := p_proof_paths;
  ELSIF p_proof_path IS NOT NULL AND btrim(p_proof_path) <> '' THEN
    v_proofs := ARRAY[btrim(p_proof_path)];
  END IF;

  IF array_length(v_proofs, 1) IS NULL OR array_length(v_proofs, 1) = 0 THEN
    RAISE EXCEPTION 'Add at least one photo showing the issue — the maker needs to see it to approve your return.'
      USING ERRCODE = 'P0001';
  END IF;

  IF array_length(v_proofs, 1) > 4 THEN
    RAISE EXCEPTION 'You can attach at most 4 photos to a return request.'
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

  -- Paid = money moved. Cash + unpaid at delivered/received means paid
  -- offline at handover (untracked); everything else unpaid/pending/failed
  -- is still rejected because there is nothing to refund.
  IF v_order.payment_status IS DISTINCT FROM 'paid'
     AND NOT (v_order.payment_method = 'cash'
              AND v_order.payment_status = 'unpaid') THEN
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
         return_proof_paths = v_proofs,
         return_proof_path = v_proofs[1]
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
  -- reference_id is UUID: pass the order id directly (no ::text cast).
  IF v_order.store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications (store_id, type, title, body, reference_id)
    VALUES (
      v_order.store_id,
      'return_request',
      'Return requested',
      'Order #' || left(p_order_id::text, 8) || ' — ' || p_reason,
      p_order_id
    );
  END IF;

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'return_requested');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_my_return(uuid, text, text, text, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_my_return(uuid, text, text, text, text[]) TO authenticated;

COMMENT ON FUNCTION public.request_my_return(uuid, text, text, text, text[]) IS
  'Customer return request. delivered/received + paid (or cash+unpaid = paid offline) + within 7 days. Mandatory 1-4 photo proofs. Writes customer + seller notifications in the same transaction.';
