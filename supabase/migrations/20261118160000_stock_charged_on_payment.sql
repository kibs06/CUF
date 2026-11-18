-- ══════════════════════════════════════════════════════════════════
-- Migration: stock leaves the shelf when the money arrives, not when the
--            customer presses "Complete Payment"
-- Date: 2026-11-18
--
-- The problem: create_gcash_checkout() deducted inventory for every line as
-- soon as the order was created (a 30-minute "hold" for the pay window).
-- Understanding the intent, the effect on the seller's product list was that
-- an UNPAID order — a customer who merely opened the GCash screen, and might
-- never pay — took units out of stock. A checkout that was then abandoned,
-- expired or cancelled churned the number again. Sellers saw stock disappear
-- for money that never arrived.
--
-- The rule from here:
--   • create_gcash_checkout  — checks availability, takes nothing;
--   • verify_gcash_payment   — the seller accepts the proof → stock is
--                              deducted in the same transaction;
--   • admin_verify_payment   — same deduction on the admin override;
--   • cancel (any cause)     — returns stock only if it was actually taken.
--
-- `orders.stock_deducted_at` is the ledger bit that makes this exact: NULL
-- means "nothing has been taken for this order", set means "it has". Every
-- release path reads it, so the two directions can never both run — which is
-- what made the old reserve/release pair safe, and what the new asymmetry
-- needs instead.
--
-- Backfill: orders created BEFORE this file were charged at creation, so
-- their units are already gone. They are stamped with created_at, which stops
-- verification from deducting a second time and keeps a later cancellation
-- honest (it returns what was really taken). Cancelled orders are skipped:
-- their release already happened.
--
-- Trade-off, stated plainly: without a hold, two customers can pay for the
-- last pair. The seller's verification is where that surfaces — the guarded
-- decrement refuses to go below zero and the seller is told the item sold out
-- while the payment was pending, so the order goes to the rejection → refund
-- path rather than shipping inventory that does not exist.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. The ledger bit
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS stock_deducted_at timestamptz;

COMMENT ON COLUMN public.orders.stock_deducted_at IS
  'When this order''s units were taken out of public.inventory. NULL = nothing taken yet (an unpaid GCash checkout), set = the stock is out and any cancellation must return it. Written only by verify_gcash_payment / admin_verify_payment, cleared by cancel_awaiting_gcash_order.';

UPDATE public.orders o
   SET stock_deducted_at = o.created_at
 WHERE o.stock_deducted_at IS NULL
   AND o.payment_method = 'gcash'
   AND o.status <> 'cancelled'
   AND EXISTS (
     SELECT 1 FROM public.order_items oi WHERE oi.order_id = o.id
   );

-- ────────────────────────────────────────────────────────────────
-- 2. create_gcash_checkout — availability only, no deduction
--    Body is otherwise identical to 20261118040000.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_gcash_checkout(
  p_items            jsonb,   -- [{product_id, size, quantity}]
  p_delivery_address text,
  p_shipping_address jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item            jsonb;
  v_product_uuid    uuid;
  v_cart_size       text;
  v_qty             int;
  v_price           numeric;
  v_list_price      numeric;
  v_sale_price      numeric;
  v_sale_start      timestamptz;
  v_sale_end        timestamptz;
  v_name            text;
  v_store_id        uuid;
  v_first_store     uuid := NULL;
  v_resolved_size   text;
  v_subtotal        numeric := 0;
  v_delivery_fee    numeric := 100;
  v_total           numeric;
  v_order_id        uuid;
  v_deadline        timestamptz;
  v_code            text;
  v_store_name      text;
  v_acct            record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Please sign in to check out';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items to order';
  END IF;

  SELECT * INTO v_acct
    FROM public.platform_payment_accounts
   WHERE is_active
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Online GCash is being set up. Please use cash on pickup for now.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT delivery_fee_amount INTO v_delivery_fee
    FROM public.platform_settings WHERE id = 1;
  v_delivery_fee := COALESCE(v_delivery_fee, 100);

  DROP TABLE IF EXISTS _checkout_items;
  CREATE TEMP TABLE _checkout_items (
    product_id uuid NOT NULL,
    size       text NOT NULL,
    quantity   int NOT NULL,
    unit_price numeric NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 0);
    IF v_item->>'product_id' IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Each item needs a product_id and a quantity greater than zero';
    END IF;
    BEGIN
      v_product_uuid := (v_item->>'product_id')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Invalid product reference in cart';
    END;

    v_cart_size := COALESCE(v_item->>'size', '');

    SELECT price, sale_price, sale_starts_at, sale_ends_at, name, store_id
      INTO v_list_price, v_sale_price, v_sale_start, v_sale_end,
           v_name, v_store_id
      FROM public.products
     WHERE id = v_product_uuid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'One of your items is no longer available. Please refresh your cart.';
    END IF;

    IF v_first_store IS NULL THEN
      v_first_store := v_store_id;
    ELSIF v_store_id <> v_first_store THEN
      RAISE EXCEPTION 'Your cart has items from more than one store. Please check out one store at a time.'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_sale_price IS NOT NULL
       AND v_sale_price > 0
       AND v_sale_price < v_list_price
       AND (v_sale_start IS NULL OR v_sale_start <= now())
       AND (v_sale_end   IS NULL OR v_sale_end   >= now())
    THEN
      v_price := v_sale_price;
    ELSE
      v_price := v_list_price;
    END IF;

    v_subtotal := v_subtotal + (v_price * v_qty);

    SELECT size INTO v_resolved_size
      FROM public.inventory
     WHERE product_id = v_product_uuid
       AND stock > 0
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(v_cart_size, '\D', '', 'g')
     LIMIT 1;
    IF v_resolved_size IS NULL AND v_cart_size = '' THEN
      SELECT size INTO v_resolved_size
        FROM public.inventory
       WHERE product_id = v_product_uuid AND stock > 0
       LIMIT 1;
    END IF;
    IF v_resolved_size IS NULL THEN
      RAISE EXCEPTION 'Size "%" is no longer available for %. Please update your cart.',
        v_cart_size, v_name
        USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO _checkout_items (product_id, size, quantity, unit_price)
    VALUES (v_product_uuid, v_resolved_size, v_qty, v_price);
  END LOOP;

  IF v_subtotal <= 0 THEN
    RAISE EXCEPTION 'Order total must be greater than zero';
  END IF;
  v_total := v_subtotal + v_delivery_fee;

  -- Enough stock to pay for, with nothing taken: the units stay sellable
  -- until this order's payment is verified.
  FOR v_item IN SELECT to_jsonb(t) FROM _checkout_items t LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory i
       WHERE i.product_id = (v_item->>'product_id')::uuid
         AND i.stock >= (v_item->>'quantity')::int
         AND regexp_replace(i.size, '\D', '', 'g')
           = regexp_replace(v_item->>'size', '\D', '', 'g')
    ) THEN
      RAISE EXCEPTION 'Insufficient stock for % (size %). Please update your cart.',
        (SELECT name FROM public.products WHERE id = (v_item->>'product_id')::uuid),
        v_item->>'size'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  BEGIN
    INSERT INTO public.orders (
      customer_id, store_id, status, fulfillment, total_amount,
      payment_method, payment_status, notes, shipping_address, source,
      payment_confirmation_deadline, payment_account_id, order_code
    ) VALUES (
      auth.uid(), v_first_store, 'awaiting_payment_confirmation', 'pickup',
      v_total, 'gcash', 'pending', p_delivery_address, p_shipping_address,
      'online', now() + interval '30 minutes', v_acct.id, v_code
    )
    RETURNING id, payment_confirmation_deadline INTO v_order_id, v_deadline;
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
       WHERE customer_id = auth.uid()
         AND status = 'awaiting_payment_confirmation'
    ) THEN
      RAISE EXCEPTION 'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.';
    END IF;
    RAISE EXCEPTION 'We could not start your checkout. Please try again.';
  END;

  INSERT INTO public.order_items (order_id, product_id, size, quantity, unit_price)
  SELECT v_order_id, product_id, size, quantity, unit_price
    FROM _checkout_items;

  -- Nothing is deducted here (see the header). stock_deducted_at stays NULL,
  -- which is what verify_gcash_payment reads to know the units are still on
  -- the shelf.
  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (v_order_id, 'created', auth.uid(),
          'Order created, awaiting GCash payment to the platform account (stock is not held; it is taken when the payment is verified)');

  SELECT name INTO v_store_name FROM public.stores WHERE id = v_first_store;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'store_id', v_first_store,
    'total_amount', v_total,
    'payment_confirmation_deadline', v_deadline,
    'store_name', v_store_name,
    'order_code', v_code,
    'payment_account_id', v_acct.id,
    'gcash_qr_url', v_acct.qr_url,
    'gcash_number', v_acct.gcash_number,
    'gcash_account_name', v_acct.account_name
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 3. verify_gcash_payment — the money is confirmed, so the stock goes
--    Body is otherwise identical to 20261118040000.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.verify_gcash_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner      uuid;
  v_customer   uuid;
  v_flagged    boolean;
  v_status     text;
  v_proof      record;
  v_updated    int;
  v_short_id   text;
  v_stock_at   timestamptz;
  v_item       record;
  v_name       text;
BEGIN
  SELECT s.owner_id, o.customer_id, o.payment_flagged, o.status,
         o.stock_deducted_at
    INTO v_owner, v_customer, v_flagged, v_status, v_stock_at
    FROM public.orders o
    JOIN public.stores s ON s.id = o.store_id
   WHERE o.id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_owner <> auth.uid() THEN
    RAISE EXCEPTION 'Only the store owner can verify this payment';
  END IF;
  IF v_status <> 'payment_under_review' THEN
    RAISE EXCEPTION 'This order is not awaiting payment verification';
  END IF;
  IF COALESCE(v_flagged, false) THEN
    RAISE EXCEPTION 'This payment is flagged by an admin. It must be cleared before you can accept it.';
  END IF;

  SELECT * INTO v_proof
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id AND status = 'pending'
   ORDER BY attempt_no DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The customer has no proof awaiting review';
  END IF;

  -- The payment is real: take the units now. Guarded, so it can never go
  -- below zero — and if the item sold out while this payment was pending the
  -- verification fails instead of shipping stock that does not exist.
  --
  -- v_stock_at is non-NULL for orders created under the old reserve-at-
  -- checkout rule (backfilled in section 1): their units are already out and
  -- deducting again would double-charge the seller's stock.
  IF v_stock_at IS NULL THEN
    FOR v_item IN
      SELECT product_id, size, quantity
        FROM public.order_items
       WHERE order_id = p_order_id
    LOOP
      UPDATE public.inventory
         SET stock = stock - v_item.quantity
       WHERE product_id = v_item.product_id
         AND regexp_replace(size, '\D', '', 'g')
           = regexp_replace(v_item.size, '\D', '', 'g')
         AND stock >= v_item.quantity;

      IF NOT FOUND THEN
        SELECT name INTO v_name FROM public.products WHERE id = v_item.product_id;
        RAISE EXCEPTION 'Insufficient stock for % (size %). It sold out while this payment was pending — reject the proof so the customer is refunded, or restock it and verify again.',
          COALESCE(v_name, 'this item'), v_item.size
          USING ERRCODE = 'P0001';
      END IF;
    END LOOP;

    UPDATE public.orders
       SET stock_deducted_at = now()
     WHERE id = p_order_id
       AND stock_deducted_at IS NULL;
  END IF;

  UPDATE public.gcash_payment_proofs
     SET status = 'verified',
         reviewed_by = auth.uid(),
         reviewed_at = now()
   WHERE id = v_proof.id;

  UPDATE public.orders
     SET status = 'pending',
         payment_status = 'paid',
         payment_verified_at = now(),
         seller_verified_at = now(),
         seller_verified_by = auth.uid(),
         review_deadline = NULL
   WHERE id = p_order_id
     AND status = 'payment_under_review';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'This order is no longer awaiting verification';
  END IF;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'seller_verified', auth.uid(),
          'Reference ' || v_proof.reference_number || ' accepted by the store' ||
          CASE WHEN v_stock_at IS NULL THEN ' (stock deducted)' ELSE '' END);

  INSERT INTO public.gcash_payment_decision_audit
    (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
  VALUES (p_order_id, auth.uid(), v_proof.reference_number, v_proof.amount_paid,
          'confirmed', 'queue');

  v_short_id := left(p_order_id::text, 8);
  IF v_customer IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (v_customer, p_order_id, 'processing',
            'Payment verified',
            'Order #' || v_short_id || ' — the store verified your GCash payment. They will start preparing your order.');
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'pending',
    'payment_status', 'paid'
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 4. admin_verify_payment — the same deduction on the admin override
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_verify_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer uuid;
  v_status   text;
  v_flagged  boolean;
  v_stock_at timestamptz;
  v_proof    record;
  v_short_id text;
  v_item     record;
  v_name     text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can verify a payment on the store''s behalf';
  END IF;

  SELECT customer_id, status, payment_flagged, stock_deducted_at
    INTO v_customer, v_status, v_flagged, v_stock_at
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status NOT IN ('payment_under_review', 'awaiting_payment_confirmation') THEN
    RAISE EXCEPTION 'This order is not awaiting payment verification';
  END IF;

  SELECT * INTO v_proof
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id AND status = 'pending'
   ORDER BY attempt_no DESC
   LIMIT 1;

  -- Money confirmed by an admin is money confirmed: same guarded deduction as
  -- the seller path, and skipped for orders whose units were already taken at
  -- checkout under the old rule.
  IF v_stock_at IS NULL THEN
    FOR v_item IN
      SELECT product_id, size, quantity
        FROM public.order_items
       WHERE order_id = p_order_id
    LOOP
      UPDATE public.inventory
         SET stock = stock - v_item.quantity
       WHERE product_id = v_item.product_id
         AND regexp_replace(size, '\D', '', 'g')
           = regexp_replace(v_item.size, '\D', '', 'g')
         AND stock >= v_item.quantity;

      IF NOT FOUND THEN
        SELECT name INTO v_name FROM public.products WHERE id = v_item.product_id;
        RAISE EXCEPTION 'Insufficient stock for % (size %). It sold out while this payment was pending — reject or cancel the order and refund the customer.',
          COALESCE(v_name, 'this item'), v_item.size
          USING ERRCODE = 'P0001';
      END IF;
    END LOOP;

    UPDATE public.orders
       SET stock_deducted_at = now()
     WHERE id = p_order_id
       AND stock_deducted_at IS NULL;
  END IF;

  -- v_proof.id, not FOUND: FOUND at this point describes the last inventory
  -- UPDATE in the loop above, not the proof SELECT.
  IF v_proof.id IS NOT NULL THEN
    UPDATE public.gcash_payment_proofs
       SET status = 'verified',
           reviewed_by = auth.uid(),
           reviewed_at = now()
     WHERE id = v_proof.id;
  END IF;

  UPDATE public.orders
     SET status = 'pending',
         payment_status = 'paid',
         payment_verified_at = now(),
         review_deadline = NULL,
         payment_flagged = false,
         payment_flag_reason = NULL
   WHERE id = p_order_id
     AND status IN ('payment_under_review', 'awaiting_payment_confirmation');

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'admin_verified', auth.uid(),
          'Payment verified by an admin' ||
          CASE WHEN v_proof.id IS NOT NULL
               THEN ' (reference ' || v_proof.reference_number || ')' ELSE '' END);

  v_short_id := left(p_order_id::text, 8);
  IF v_customer IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (v_customer, p_order_id, 'processing',
            'Payment verified',
            'Order #' || v_short_id || ' — your GCash payment was verified. The store will start preparing your order.');
  END IF;

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'pending');
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 5. Cancellation returns only what was taken
--    Same helper as 20261118130000 (refund bookkeeping untouched); the only
--    change is that the stock release is conditional on the ledger bit.
-- ────────────────────────────────────────────────────────────────
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
  v_customer_id  uuid;
  v_updated      int;
  v_short_id     text;
  v_refund_owed  boolean := false;
  v_stock_at     timestamptz;
  r              record;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id
  ) INTO v_refund_owed;

  UPDATE public.orders
     SET status = 'cancelled',
         payment_status = CASE WHEN v_refund_owed THEN 'refund_pending'
                               ELSE 'failed' END,
         cancellation_reason = p_reason,
         cancellation_details = p_details,
         cancelled_at = now()
   WHERE id = p_order_id
     AND status = 'awaiting_payment_confirmation'
   RETURNING customer_id, stock_deducted_at INTO v_customer_id, v_stock_at;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN false;  -- already confirmed/rejected/expired/cancelled
  END IF;

  -- Return the units ONLY if this order really took them. An unpaid checkout
  -- never did (stock_deducted_at is NULL), so cancelling it must not put stock
  -- back that another customer's order is holding.
  IF v_stock_at IS NOT NULL THEN
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

    UPDATE public.orders
       SET stock_deducted_at = NULL
     WHERE id = p_order_id;
  ELSE
    DELETE FROM public.order_items WHERE order_id = p_order_id;
  END IF;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, p_event, p_actor_id, p_details);

  IF p_notify_customer AND v_customer_id IS NOT NULL THEN
    v_short_id := left(p_order_id::text, 8);
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_customer_id,
      p_order_id,
      'returns',
      CASE WHEN p_event = 'expired' THEN 'Payment window expired'
           WHEN p_event = 'cancelled_by_customer' THEN 'GCash checkout cancelled'
           WHEN v_refund_owed THEN 'Payment rejected — refund on the way'
           ELSE 'Payment rejected' END,
      'Order #' || v_short_id || ' — ' || p_details ||
        CASE WHEN v_refund_owed
             THEN '. The money you sent is in the platform GCash account and ' ||
                  'CUFMAI will send it back to your GCash.'
             ELSE '' END
    );
  END IF;

  RETURN true;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 6. Grants (re-stated; CREATE OR REPLACE keeps the ACL, this makes the
--    intent visible next to the bodies)
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_gcash_payment(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.verify_gcash_payment(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_verify_payment(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_verify_payment(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_awaiting_gcash_order(uuid, text, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT count(*) FROM public.orders
--  WHERE payment_method = 'gcash' AND stock_deducted_at IS NULL
--    AND status = 'awaiting_payment_confirmation';   -- unpaid: nothing held
-- SELECT stock_deducted_at IS NOT NULL AS charged, count(*)
--   FROM public.orders WHERE payment_method = 'gcash'
--   GROUP BY 1;
