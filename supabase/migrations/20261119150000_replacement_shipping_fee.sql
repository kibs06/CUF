-- ══════════════════════════════════════════════════════════════════
-- Replacement shipping fee (Carcar City deliveries)
-- Date: 2026-11-19
--
-- House rule for returns: a replacement is free, but when it is DELIVERED to
-- an address inside Carcar City the customer pays one fixed ₱50 shipping fee.
-- Addresses outside Carcar City are not shipped at all — the customer brings
-- the pair to the store and collects the replacement there.
--
-- This migration makes that fee real rather than a paragraph in the Terms:
--   • the seller's approval records the fee on the order it applies to;
--   • the customer submits the GCash reference of the ₱50 they sent;
--   • the store confirms it received the money, which is what unlocks the
--     shipped path in the seller app.
--
-- Nothing here charges a card or moves money: like the rest of manual GCash,
-- the transfer is made in the GCash app and verified by the store.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS replacement_shipping_fee   NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replacement_fee_status     TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS replacement_fee_reference  TEXT,
  ADD COLUMN IF NOT EXISTS replacement_fee_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS replacement_fee_paid_at    TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.replacement_shipping_fee IS
  'Flat ₱50 fee the customer pays when the replacement is delivered inside Carcar City. 0 for in-store handovers and for orders approved before this rule.';
COMMENT ON COLUMN public.orders.replacement_fee_status IS
  'none = no fee applies, due = waiting on the customer''s GCash reference, submitted = reference sent and waiting on the store, paid = store confirmed the transfer.';
COMMENT ON COLUMN public.orders.replacement_fee_reference IS
  'GCash reference the customer typed for the replacement shipping fee.';
COMMENT ON COLUMN public.orders.replacement_fee_paid_at IS
  'When the store confirmed the ₱50 replacement shipping fee arrived.';

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_replacement_fee_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_replacement_fee_status_check
    CHECK (replacement_fee_status IN ('none', 'due', 'submitted', 'paid'));

-- A submitted fee is a new kind of seller notification, so the bell can show
-- it and the push has something to point at.
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
        'return_request',
        'new_review',
        'review_comment',
        'replacement_received',
        'replacement_fee',
        'verified_seller',
        'permit_expiring'
      )
    );

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_replacement_shipping_fee_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_replacement_shipping_fee_check
    CHECK (replacement_shipping_fee >= 0);

-- ── 1. Customer: submit the reference of the ₱50 they sent ─────────────
CREATE OR REPLACE FUNCTION public.submit_replacement_fee(
  p_order_id uuid,
  p_reference text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  -- The bell is keyed by STORE and `orders.store_id` is nullable, so the id is
  -- read into a local before it is used as a recipient: a NULL there is a
  -- 23502 that would roll back the customer's own submission.
  v_store_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_reference IS NULL OR length(btrim(p_reference)) < 4 THEN
    RAISE EXCEPTION 'Type the GCash reference of your ₱50 transfer'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  IF v_order.id IS NULL OR v_order.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = '42501';
  END IF;

  IF v_order.replacement_method IS DISTINCT FROM 'shipped' THEN
    RAISE EXCEPTION 'This replacement is collected in store — no shipping fee applies'
      USING ERRCODE = 'P0001';
  END IF;

  IF coalesce(v_order.replacement_shipping_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'This replacement has no shipping fee'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.replacement_fee_status = 'paid' THEN
    RAISE EXCEPTION 'The shipping fee is already paid'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.replacement_fee_status = 'submitted' THEN
    RAISE EXCEPTION 'You already submitted a reference — the store is checking it'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
     SET replacement_fee_status = 'submitted',
         replacement_fee_reference = btrim(p_reference),
         replacement_fee_submitted_at = now()
   WHERE id = p_order_id;

  -- Tell the store in-app, the same way a GCash payment proof does. Without
  -- this the reference sat on the order until someone opened it, and the
  -- dispatch gate stalled behind that.
  v_store_id := v_order.store_id;
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id,
      'replacement_fee',
      'Replacement shipping fee submitted',
      'Order #' || left(p_order_id::text, 8) || ' — the customer sent the ₱'
        || trim(to_char(coalesce(v_order.replacement_shipping_fee, 0), 'FM999999990'))
        || ' reference (' || btrim(p_reference) || '). Confirm it before dispatch.',
      p_order_id
    );
  END IF;

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'submitted');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_replacement_fee(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_replacement_fee(uuid, text) TO authenticated;

-- ── 2. Store: confirm the ₱50 landed ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_replacement_fee(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.stores s
     WHERE s.id = v_order.store_id AND s.owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the store shipping this replacement can confirm its fee'
      USING ERRCODE = '42501';
  END IF;

  IF v_order.replacement_fee_status = 'paid' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', 'paid');
  END IF;

  IF v_order.replacement_fee_status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'The customer has not submitted a reference yet'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
     SET replacement_fee_status = 'paid',
         replacement_fee_paid_at = now()
   WHERE id = p_order_id;

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'paid');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_replacement_fee(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_replacement_fee(uuid) TO authenticated;

COMMENT ON FUNCTION public.submit_replacement_fee(uuid, text) IS
  'Customer submits the GCash reference of the fixed ₱50 replacement shipping fee for a shipped Carcar City replacement.';
COMMENT ON FUNCTION public.confirm_replacement_fee(uuid) IS
  'Store confirms the ₱50 replacement shipping fee arrived, which unlocks shipping the replacement.';
