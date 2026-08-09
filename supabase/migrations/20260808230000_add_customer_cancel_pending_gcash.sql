-- ══════════════════════════════════════════════════════════════════
-- Customer self-service cancel for gateway-free GCash checkouts
--
-- The one-open-order-per-customer guard (partial unique index) blocks a
-- second checkout while an 'awaiting_payment_confirmation' order exists,
-- but until now the customer had no in-app way to act on that order from
-- the checkout screen: resume lived on the tracking screen, and cancel
-- meant waiting for the 30-minute expiry sweep. This adds:
--
--   1. 'cancelled_by_customer' to the order_payment_events CHECK so the
--      append-only audit log can record customer-initiated cancels.
--   2. cancel_my_pending_gcash_checkout(uuid) — SECURITY DEFINER RPC,
--      customer-own-only, reuses the guarded cancel helper (exactly-once
--      stock release + audit event + customer notification).
--
-- Money-safety rule: a customer may NOT cancel once proof of payment was
-- submitted — the money may already have moved to the seller, so the
-- store must confirm or reject it. Only unpaid reservations are
-- self-cancellable. Deadlines: cancelling works at any time while the
-- status is still 'awaiting_payment_confirmation' (even past the window,
-- before the sweep runs) — the guarded transition resolves it early.
-- ══════════════════════════════════════════════════════════════════

-- 1. Extend the audit-log event CHECK with the new event type.
ALTER TABLE public.order_payment_events
    DROP CONSTRAINT IF EXISTS order_payment_events_event_type_check;

ALTER TABLE public.order_payment_events
    ADD CONSTRAINT order_payment_events_event_type_check
    CHECK (event_type IN
      ('created', 'proof_submitted', 'confirmed', 'rejected', 'expired',
       'cancelled_by_customer'));

-- 2. Recreate the guarded cancel helper with a correct notification
--    title for the customer-initiated case (the old CASE read "Payment
--    rejected" for anything non-expired, which would be wrong here).
CREATE OR REPLACE FUNCTION public.cancel_awaiting_gcash_order(
  p_order_id uuid,
  p_reason   text,
  p_details  text,
  p_event    text,          -- 'rejected' | 'expired' | 'cancelled_by_customer'
  p_actor_id uuid,          -- NULL for the automated sweep
  p_notify_customer boolean
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_updated     int;
  v_short_id    text;
  r             record;
BEGIN
  -- Guarded transition: only transitions an order that is still awaiting.
  -- Row lock serializes concurrent confirm/reject/expiry/cancel.
  UPDATE public.orders
     SET status = 'cancelled',
         payment_status = 'failed',
         cancellation_reason = p_reason,
         cancellation_details = p_details,
         cancelled_at = now()
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation'
   RETURNING customer_id INTO v_customer_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN false;  -- already confirmed/rejected/expired/cancelled
  END IF;

  -- Release reserved stock exactly once (serialized with the row lock
  -- acquired by the UPDATE above).
  FOR r IN
      DELETE FROM public.order_items
      WHERE order_id = p_order_id
      RETURNING product_id, size, quantity
  LOOP
    UPDATE public.inventory
       SET stock = stock + r.quantity
     WHERE product_id = r.product_id
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(r.size, '\D', '', 'g');
  END LOOP;

  -- Audit event (append-only).
  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, p_event, p_actor_id, p_details);

  -- Customer in-app notification (lands in notifications, read on open).
  IF p_notify_customer THEN
    v_short_id := left(p_order_id::text, 8);
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_customer_id,
      p_order_id,
      'returns',
      CASE WHEN p_event = 'expired' THEN 'Payment window expired'
           WHEN p_event = 'cancelled_by_customer' THEN 'GCash checkout cancelled'
           ELSE 'Payment rejected' END,
      'Order #' || v_short_id || ' — ' || p_details
    );
  END IF;

  RETURN true;
END;
$$;

-- 3. Customer-facing cancel RPC: ownership + state + no-proof checks,
--    then delegates to the guarded helper.
CREATE OR REPLACE FUNCTION public.cancel_my_pending_gcash_checkout(
  p_order_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.orders%ROWTYPE;
  v_proof_exists boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
    FROM public.orders
   WHERE id = p_order_id;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Order not found'
      USING ERRCODE = '42501';
  END IF;

  IF v_row.customer_id <> auth.uid() THEN
    RAISE EXCEPTION 'You can only cancel your own orders'
      USING ERRCODE = '42501';
  END IF;

  IF v_row.status <> 'awaiting_payment_confirmation' THEN
    RETURN false;  -- already resolved (paid/rejected/expired/cancelled)
  END IF;

  -- Money-safety: once proof is submitted the transfer may have happened —
  -- the store must confirm or reject; the customer cannot silently unwind.
  SELECT EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id
  ) INTO v_proof_exists;

  IF v_proof_exists THEN
    RAISE EXCEPTION
      'Your payment proof was already submitted. Please wait for the store to confirm it, or contact the store to cancel.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN public.cancel_awaiting_gcash_order(
    p_order_id,
    'Cancelled by customer',
    'Cancelled by customer',
    'cancelled_by_customer',
    auth.uid(),
    true
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_my_pending_gcash_checkout(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_my_pending_gcash_checkout(uuid) TO authenticated;
