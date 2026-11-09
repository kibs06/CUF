-- ══════════════════════════════════════════════════════════════════
-- Migration: customer returns & refunds (matches Customer Terms & Privacy)
-- Date: 2026-11-10
--
-- Terms promise:
--   • 7-day return window from delivery, unworn/unused + original packaging
--   • Refund to original payment method within 5–7 business days after
--     inspection
--   • Buyer pays return shipping unless defective/incorrect
--   • Defective/incorrect: contact within 48h, prepaid label + replacement
--
-- What this adds:
--   • orders.return_reason / return_details / return_requested_at /
--     refunded_at
--   • statuses 'return_requested' (customer asks, seller decides) and
--     'refunded' (terminal, seller inspected + refunded)
--   • SECURITY DEFINER RPC request_my_return() — the ONLY customer write
--     path (orders has no customer UPDATE policy; see
--     20260925140000_add_cancel_my_order_rpc.sql for why a policy widen
--     would leak payment columns)
--   • 'return_request' admitted to seller_notifications_type_check so the
--     store bell can render the request
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Columns ────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_reason TEXT;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_details TEXT;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_requested_at TIMESTAMPTZ;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.return_reason IS
  'Customer return reason (see AppConstants.returnReasons); free text required when Other';
COMMENT ON COLUMN public.orders.return_details IS
  'Extra detail when reason is Other';
COMMENT ON COLUMN public.orders.return_requested_at IS
  'When the customer requested a return';
COMMENT ON COLUMN public.orders.refunded_at IS
  'When the seller marked the order refunded';

-- ── 2. Status CHECK (superset of every value ever allowed) ───────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN (
      'pending', 'placed', 'preparing', 'ready', 'delivered',
      'received', 'cancelled', 'cancellation_requested',
      'awaiting_payment', 'payment_conflict',
      'awaiting_payment_confirmation',
      'return_requested', 'refunded'
    ));

-- ── 3. Seller bell type ───────────────────────────────────────────
ALTER TABLE public.seller_notifications
  DROP CONSTRAINT IF EXISTS seller_notifications_type_check;
ALTER TABLE public.seller_notifications
  ADD CONSTRAINT seller_notifications_type_check
    CHECK (
      type IN (
        'new_order',
        'stale_order',
        'low_stock',
        'custom_order_request',
        'new_message',
        'model_request',
        'return_request'
      )
    );

-- ── 4. RPC: customer requests a return ────────────────────────────
-- Rules (mirror the Terms + app):
--   • own orders only, status delivered/received, payment_status paid
--   • within 7 days of delivery (delivered/received history row, else
--     created_at fallback); defective/incorrect items are still asked to
--     file within the same window — the 48h rule is rendered as guidance
--     in the sheet, not a second hard gate
--   • one request only (return_requested/refunded cannot re-request)
CREATE OR REPLACE FUNCTION public.request_my_return(
  p_order_id uuid,
  p_reason   text,
  p_details  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
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
         return_requested_at = now()
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

REVOKE EXECUTE ON FUNCTION public.request_my_return(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_my_return(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.request_my_return(uuid, text, text) IS
  'Customer return request. delivered/received + paid + within 7 days of delivery. Own orders only. Writes customer + seller notifications in the same transaction.';
