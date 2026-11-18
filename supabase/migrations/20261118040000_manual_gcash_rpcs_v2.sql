-- ══════════════════════════════════════════════════════════════════
-- Migration: Manual GCash v2 — RPCs
-- Date: 2026-11-18
-- Depends on: 20261118020000 (platform account), 20261118030000 (v2 schema)
--
-- The whole payment lifecycle lives here. The client never writes payment
-- state: every transition is one SECURITY DEFINER function with an explicit
-- ownership check, a guarded UPDATE and an append-only event.
--
-- Lifecycle (per order):
--   create_gcash_checkout   → awaiting_payment_confirmation (30 min pay window)
--   submit_gcash_proof      → payment_under_review (24 h SLA, never expires)
--   verify_gcash_payment    → pending / paid        (seller; can ship)
--   reject_gcash_proof      → back to awaiting (attempts 1-2), cancelled (3)
--   admin_flag_payment      → excluded from payouts until cleared
--   admin_verify_payment    → admin override of the seller step
--   admin_reconcile_order   → funds seen in the platform statement
--   expire_unpaid_gcash_orders → cancels ONLY orders with no proof at all
--
-- Why the admin can never be bypassed: `verify_gcash_payment` marks the
-- payment paid, but `admin_reconcile_order` (a separate admin-only action)
-- is what puts an order into a payout. A seller who confirms a payment that
-- never landed gets no money.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. create_gcash_checkout (customer)
--    Replaces the version whose EXECUTE was revoked on 2026-09-05. The
--    route is deliberately re-opened here — this is now the marketplace's
--    real online payment path, not an experiment.
--
--    Changes vs the previous body:
--      • pays the PLATFORM account (active row), not the seller's;
--      • refuses a cross-store cart (the old body silently billed the
--        whole cart to the first product's store, which would have paid
--        the wrong seller);
--      • generates the customer-facing order_code;
--      • delivery fee comes from platform_settings, not a literal 100;
--      • stamps payment_account_id for the audit trail.
--    Pricing (list vs sale) is unchanged from 20260925130000.
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

  -- Exactly one active platform account, or no checkout at all: showing a
  -- customer a different number than the one the admin watches would make
  -- every order unverifiable.
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

  -- ON COMMIT DROP only fires at the end of the transaction, so two
  -- checkouts in one transaction (a batched client, or a test) would trip
  -- over the leftover table. Drop it first: the function must be callable
  -- more than once per transaction.
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

    -- A cross-store cart cannot be paid to one account and fulfilled by
    -- one seller: refuse it explicitly instead of charging the first store.
    IF v_first_store IS NULL THEN
      v_first_store := v_store_id;
    ELSIF v_store_id <> v_first_store THEN
      RAISE EXCEPTION 'Your cart has items from more than one store. Please check out one store at a time.'
        USING ERRCODE = 'P0001';
    END IF;

    -- Effective price: isOnSale() from lib/utils/sale_price.dart, in SQL.
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
    -- The only other unique value is the generated order code: vanishingly
    -- rare, and the customer can simply retry.
    RAISE EXCEPTION 'We could not start your checkout. Please try again.';
  END;

  INSERT INTO public.order_items (order_id, product_id, size, quantity, unit_price)
  SELECT v_order_id, product_id, size, quantity, unit_price
    FROM _checkout_items;

  -- Reserve the stock now, for the payment window. The release path is
  -- cancel_awaiting_gcash_order(), which adds these quantities back from
  -- the deleted lines — exactly once.
  FOR v_item IN SELECT to_jsonb(t) FROM _checkout_items t LOOP
    UPDATE public.inventory
       SET stock = stock - (v_item->>'quantity')::int
     WHERE product_id = (v_item->>'product_id')::uuid
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(v_item->>'size', '\D', '', 'g')
       AND stock >= (v_item->>'quantity')::int;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient stock for % (size %). Please update your cart.',
        (SELECT name FROM public.products WHERE id = (v_item->>'product_id')::uuid),
        v_item->>'size'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (v_order_id, 'created', auth.uid(),
          'Order created, stock reserved, awaiting GCash payment to the platform account');

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
-- 2. submit_gcash_proof (customer)
--    Attempt 1..3. Replaces the one-shot version: a rejected proof used to
--    mean a cancelled order, so a single mistyped digit destroyed a real
--    payment. Now a rejection returns the order to the customer.
--
--    Server-side checks a screenshot cannot fake:
--      • the amount entered must equal the order total;
--      • the reference must be unique platform-wide (existing constraint);
--      • the screenshot hash must be unique platform-wide (new);
--      • the path must live in this order's own folder.
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
-- 3. verify_gcash_payment (seller)
--    The seller accepts the proof → the order enters the normal pipeline.
--    A flagged payment cannot be accepted until an admin clears it.
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
BEGIN
  SELECT s.owner_id, o.customer_id, o.payment_flagged, o.status
    INTO v_owner, v_customer, v_flagged, v_status
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
          'Reference ' || v_proof.reference_number || ' accepted by the store');

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
-- 4. reject_gcash_proof (seller)
--    Rejection is a PROOF decision, not an order-killer: attempts 1 and 2
--    return the order to the customer with a fresh 30-minute window; the
--    third rejection cancels the order and releases the reserved stock.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_gcash_proof(
  p_order_id uuid,
  p_reason   text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner     uuid;
  v_customer  uuid;
  v_status    text;
  v_proof     record;
  v_reason    text;
  v_short_id  text;
  v_cancelled boolean := false;
BEGIN
  SELECT s.owner_id, o.customer_id, o.status
    INTO v_owner, v_customer, v_status
    FROM public.orders o
    JOIN public.stores s ON s.id = o.store_id
   WHERE o.id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_owner <> auth.uid() THEN
    RAISE EXCEPTION 'Only the store owner can reject this payment';
  END IF;
  IF v_status <> 'payment_under_review' THEN
    RAISE EXCEPTION 'This order is not awaiting payment verification';
  END IF;

  v_reason := btrim(COALESCE(p_reason, ''));
  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'Please give the customer a reason (at least 3 characters)';
  END IF;

  SELECT * INTO v_proof
    FROM public.gcash_payment_proofs
   WHERE order_id = p_order_id AND status = 'pending'
   ORDER BY attempt_no DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The customer has no proof awaiting review';
  END IF;

  UPDATE public.gcash_payment_proofs
     SET status = 'rejected',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         rejection_reason = v_reason
   WHERE id = v_proof.id;

  INSERT INTO public.gcash_payment_decision_audit
    (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
  VALUES (p_order_id, auth.uid(), v_proof.reference_number, v_proof.amount_paid,
          'rejected', 'queue');

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'rejected', auth.uid(),
          'Attempt ' || v_proof.attempt_no || ' rejected: ' || v_reason);

  v_short_id := left(p_order_id::text, 8);

  IF v_proof.attempt_no >= 3 THEN
    -- Final attempt: cancel through the shared helper (exactly-once stock
    -- release + customer notification).
    UPDATE public.orders
       SET status = 'awaiting_payment_confirmation',
           review_deadline = NULL
     WHERE id = p_order_id
       AND status = 'payment_under_review';

    v_cancelled := public.cancel_awaiting_gcash_order(
      p_order_id,
      'Payment rejected by seller',
      v_reason,
      'rejected',
      auth.uid(),
      true
    );

    RETURN jsonb_build_object(
      'order_id', p_order_id,
      'status', 'cancelled',
      'attempt_no', v_proof.attempt_no,
      'cancelled', v_cancelled
    );
  END IF;

  -- Another chance: back to the pay window with a fresh 30 minutes.
  UPDATE public.orders
     SET status = 'awaiting_payment_confirmation',
         payment_confirmation_deadline = now() + interval '30 minutes',
         review_deadline = NULL
   WHERE id = p_order_id
     AND status = 'payment_under_review';

  IF v_customer IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (v_customer, p_order_id, 'returns',
            'Payment proof rejected',
            'Order #' || v_short_id || ' — ' || v_reason ||
              '. You can submit a corrected proof (' ||
              (3 - v_proof.attempt_no) || ' attempt(s) left).');
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status', 'awaiting_payment_confirmation',
    'attempt_no', v_proof.attempt_no,
    'attempts_left', 3 - v_proof.attempt_no
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 5. Admin actions
--    All admin-only (checked inside the function: is_admin() reads the
--    caller's profile, so granting EXECUTE to authenticated is safe).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_flag_payment(
  p_order_id uuid,
  p_reason   text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can flag a payment';
  END IF;
  v_reason := btrim(COALESCE(p_reason, ''));
  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'A flag needs a reason';
  END IF;

  UPDATE public.orders
     SET payment_flagged = true,
         payment_flag_reason = v_reason
   WHERE id = p_order_id
     AND payment_status <> 'failed';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or already failed';
  END IF;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'flagged', auth.uid(), v_reason);

  RETURN jsonb_build_object('order_id', p_order_id, 'payment_flagged', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_clear_payment_flag(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can clear a payment flag';
  END IF;

  UPDATE public.orders
     SET payment_flagged = false,
         payment_flag_reason = NULL
   WHERE id = p_order_id
     AND payment_flagged;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'unflagged', auth.uid(), 'Flag cleared by admin');

  RETURN jsonb_build_object('order_id', p_order_id, 'payment_flagged', false);
END;
$$;

-- Admin override of the seller step (seller inactive, or the proof is
-- obviously valid and the seller is not responding).
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
  v_proof    record;
  v_short_id text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can verify a payment on the store''s behalf';
  END IF;

  SELECT customer_id, status, payment_flagged
    INTO v_customer, v_status, v_flagged
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

  IF FOUND THEN
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

-- "I saw this exact amount in the platform GCash statement."
CREATE OR REPLACE FUNCTION public.admin_reconcile_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_paid    text;
  v_flagged boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can reconcile payments';
  END IF;

  SELECT payment_status, payment_flagged
    INTO v_paid, v_flagged
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_paid <> 'paid' THEN
    RAISE EXCEPTION 'This order is not marked as paid yet';
  END IF;
  IF COALESCE(v_flagged, false) THEN
    RAISE EXCEPTION 'Clear the payment flag before reconciling';
  END IF;

  UPDATE public.orders
     SET funds_reconciled_at = now(),
         funds_reconciled_by = auth.uid()
   WHERE id = p_order_id;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'funds_reconciled', auth.uid(),
          'Funds confirmed in the platform GCash statement');

  RETURN jsonb_build_object('order_id', p_order_id, 'funds_reconciled', true);
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 6. expire_unpaid_gcash_orders — only orders with NO proof.
--    A paid-looking order is never cancelled by a timer.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_unpaid_gcash_orders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order uuid;
  v_count int := 0;
BEGIN
  FOR v_order IN
    SELECT o.id
      FROM public.orders o
     WHERE o.status = 'awaiting_payment_confirmation'
       AND o.payment_confirmation_deadline < now()
       AND NOT EXISTS (
         SELECT 1 FROM public.gcash_payment_proofs p WHERE p.order_id = o.id
       )
  LOOP
    IF public.cancel_awaiting_gcash_order(
         v_order,
         'Payment window expired',
         'No GCash payment was submitted within the allowed window. Stock released.',
         'expired',
         NULL,
         true) THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('expired', v_count);
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 6b. Retire the superseded 3-argument submit_gcash_proof
--    It recorded a proof with NO amount, NO screenshot hash and NO attempt
--    bookkeeping, and was still granted to `authenticated`. Leaving it
--    callable would let a caller skip every v2 rule (amount equality,
--    hash dedupe, the 3-attempt cap) simply by using the old signature.
--    The 7-argument version above is the only way in.
-- ────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.submit_gcash_proof(uuid, text, text);

-- ────────────────────────────────────────────────────────────────
-- 6c. One expiry policy, whatever the cron calls
--    expire_overdue_gcash_orders() was scheduled by 20260808210000 and
--    cancels ANY awaiting_payment_confirmation order past its deadline —
--    including one whose proof was just rejected, which would silently
--    defeat the 3-attempt rule. Point the old name at the new sweep so a
--    pre-existing cron job cannot cancel an order the customer may still
--    pay for.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_overdue_gcash_orders()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.expire_unpaid_gcash_orders();
$$;

-- ────────────────────────────────────────────────────────────────
-- 6d. Nothing else to install here — the reservation lives in the
--     create_gcash_checkout body above (section 1), deliberately.
--
--     The chain defines decrement_inventory_on_order() but attaches it to
--     NO table, and attaching it globally is wrong: the pickup-reservation
--     flows decrement inventory themselves, so a trigger on order_items
--     double-decrements them (13 assertions in pickup_reservations /
--     pickup_codes fail). This RPC therefore takes the stock itself, and
--     cancel_awaiting_gcash_order() returns it — symmetric, local, and it
--     leaves the other order paths exactly as they were.
-- ────────────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────
-- 7. Grants
--    Re-opens the customer creation route deliberately, and keeps the
--    private helper owner-only.
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.submit_gcash_proof(uuid, text, text, numeric, text, text, timestamptz) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.submit_gcash_proof(uuid, text, text, numeric, text, text, timestamptz) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_gcash_payment(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.verify_gcash_payment(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.reject_gcash_proof(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.reject_gcash_proof(uuid, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_flag_payment(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_flag_payment(uuid, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_clear_payment_flag(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_clear_payment_flag(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_verify_payment(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_verify_payment(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_reconcile_order(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_reconcile_order(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.expire_unpaid_gcash_orders() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.expire_unpaid_gcash_orders() TO authenticated;

-- The customer may re-open their own checkout after a rejection.
REVOKE EXECUTE ON FUNCTION public.cancel_my_pending_gcash_checkout(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.cancel_my_pending_gcash_checkout(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 8. pg_cron sweep (guarded, same pattern as the previous migrations)
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-unpaid-gcash-orders') THEN
    PERFORM cron.schedule(
      'expire-unpaid-gcash-orders',
      '*/5 * * * *',
      $cron$ SELECT public.expire_unpaid_gcash_orders(); $cron$
    );
    RAISE NOTICE 'Scheduled pg_cron job: expire-unpaid-gcash-orders (every 5 min)';
  ELSE
    RAISE NOTICE 'pg_cron unavailable — expiry enforced by app calls to expire_unpaid_gcash_orders().';
  END IF;
EXCEPTION
  WHEN undefined_table OR insufficient_privilege OR undefined_function THEN
    RAISE NOTICE 'pg_cron unavailable — expiry enforced by app calls to expire_unpaid_gcash_orders().';
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT proname, pronargs, prosecdef FROM pg_proc
--  WHERE proname IN ('create_gcash_checkout','submit_gcash_proof',
--                    'verify_gcash_payment','reject_gcash_proof',
--                    'admin_flag_payment','admin_clear_payment_flag',
--                    'admin_verify_payment','admin_reconcile_order',
--                    'expire_unpaid_gcash_orders')
--  ORDER BY proname;
-- SELECT has_function_privilege('authenticated',
--   'public.create_gcash_checkout(jsonb, text, jsonb)', 'EXECUTE');
