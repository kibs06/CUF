-- ══════════════════════════════════════════════════════════════════
-- Migration: Direct (gateway-free) GCash online checkout — RPCs
-- Date: 2026-08-08
-- Depends on: 20260808200000_add_direct_gcash_online_checkout.sql (schema)
--
-- Purpose: SECURITY DEFINER Postgres functions that drive the
--          gateway-free GCash flow. The client NEVER writes payment
--          status directly — every transition (create / submit proof /
--          confirm / reject / expire) goes through exactly one of these
--          functions, each with explicit ownership checks
--          (orders.customer_id = auth.uid() or stores.owner_id =
--          auth.uid()), atomic transitions, and audit events.
--
-- Why Postgres RPCs instead of Edge Functions (confirmed decision):
--   • create_gcash_checkout inserts the order AND its order_items in ONE
--     transaction → the existing decrement_inventory_on_order trigger
--     decrements stock atomically and rejects oversell (P0001) with a
--     full rollback — no orphaned orders, no partial reservations.
--   • No service-role secret anywhere; auth.uid() flows automatically.
--   • No gateway → the seller's confirmation tap is the security
--     control; these functions protect it.
--
-- State machine:
--   awaiting_payment_confirmation --confirm_gcash_payment--> pending / paid
--        |  (stock reserved at creation)
--        +--reject_gcash_payment-----------> cancelled / failed, stock released
--        +--expire_overdue_gcash_orders()--> cancelled / failed, stock released
--
-- Race handling (confirm vs reject vs expiry):
--   Every terminal transition is a single guarded UPDATE
--   (WHERE status = 'awaiting_payment_confirmation') inside one
--   transaction — the row lock serializes concurrent callers, and the
--   first to land wins. Losers get a clean "no longer awaiting" error
--   (confirm/reject) or a silent no-op (expiry sweep).
--
-- Deadline decisions (documented, brief §6.3):
--   • Submission EXTENDS the clock: proof submitted → the deadline moves
--     to now() + 2 hours, so a paid order is never expired out from under
--     the customer while the seller verifies.
--   • Confirm AFTER the deadline is still ALLOWED: the seller's own
--     verification is the stronger signal than the timer (money was
--     received per the seller's GCash app). Expiry only ever releases
--     stock for orders the seller did NOT confirm.
--
-- Stock release is exactly-once by construction: the helper deletes the
-- order_items rows and re-increments inventory from the DELETED rows
-- (DELETE ... RETURNING). A second call deletes 0 rows and increments
-- nothing — no double-release.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 0. FIX order_id type (BIGINT → UUID) on notifications AND
--    order_status_history
--    The live DB uses UUID for orders.id. notifications.order_id was
--    created BIGINT → every app-side customer notification insert with
--    an order id fails silently today. order_status_history.order_id is
--    the same family — and the existing record_order_status_change
--    trigger inserts new.id (a UUID) into it, so if that column were
--    still BIGINT, EVERY status transition (including the new
--    confirm/reject/expire transitions in this migration) would abort.
--    Conditional: only re-types when the column is actually BIGINT, so
--    applying on a DB where it is already UUID is a safe no-op. Legacy
--    bigint values are meaningless (they could never reference a UUID
--    order) → nulled.
-- ────────────────────────────────────────────────────────────────
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['notifications', 'order_status_history'] LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = t
        AND column_name = 'order_id' AND data_type = 'bigint'
    ) THEN
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I',
        t, t || '_order_id_fkey');
      EXECUTE format('ALTER TABLE public.%I ALTER COLUMN order_id TYPE uuid USING NULL', t);
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE',
        t, t || '_order_id_fkey');
    END IF;
  END LOOP;
END
$$;

-- ────────────────────────────────────────────────────────────────
-- 1. PRIVATE HELPER: guarded cancel + release + event + notify
--    Returns true if this call performed the cancellation (first
--    caller wins), false if the order already left
--    awaiting_payment_confirmation (no-op — racing confirm/expiry).
--    Never granted to authenticated users — internal only.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_awaiting_gcash_order(
  p_order_id uuid,
  p_reason   text,
  p_details  text,
  p_event    text,          -- 'rejected' | 'expired'
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
  -- Row lock serializes concurrent confirm/reject/expiry on this order.
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
    RETURN false;  -- already confirmed/rejected/expired — nothing to do
  END IF;

  -- Release reserved stock exactly once: increment from the DELETED rows.
  -- (Edge: if the seller deleted the inventory row between reservation and
  -- release, the increment matches 0 rows — rare, accepted, noted.)
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

  -- Customer in-app notification (fires even when the customer app is
  -- closed — it lands in the notifications table, read on next open).
  IF p_notify_customer THEN
    v_short_id := left(p_order_id::text, 8);
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_customer_id,
      p_order_id,
      'returns',
      CASE WHEN p_event = 'expired' THEN 'Payment window expired'
           ELSE 'Payment rejected' END,
      'Order #' || v_short_id || ' — ' || p_details
    );
  END IF;

  RETURN true;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 2. create_gcash_checkout (customer, JWT)
--    Validates + recomputes everything server-side, then atomically:
--      • inserts the order (awaiting_payment_confirmation, 30-min
--        deadline, payment_status='pending')
--      • inserts order_items → existing trigger decrements stock and
--        rejects oversell (P0001 → full rollback, clean error)
--      • logs the 'created' event
--    Returns the order + the store's GCash payment details so the
--    checkout UI can show the seller's QR / number / account name.
--    Enforced by the schema's partial unique index: at most ONE open
--    awaiting-payment-confirmation order per customer.
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
  v_name            text;
  v_store_id        uuid;
  v_first_store     uuid := NULL;
  v_resolved_size   text;
  v_subtotal        numeric := 0;
  v_total           numeric;
  v_order_id        uuid;
  v_deadline        timestamptz;
  v_store_name      text;
  v_qr              text;
  v_number          text;
  v_account         text;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items to order';
  END IF;

  -- Pass 1: validate items, pin prices (server-side, never client-trusted),
  -- resolve the exact inventory size for each line.
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

    SELECT price, name, store_id
      INTO v_price, v_name, v_store_id
      FROM public.products
     WHERE id = v_product_uuid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'One of your items is no longer available. Please refresh your cart.';
    END IF;

    IF v_first_store IS NULL THEN v_first_store := v_store_id; END IF;
    v_subtotal := v_subtotal + (v_price * v_qty);

    -- Resolve size exactly like the app (normalized match first; a
    -- sizeless item falls back to any in-stock row).
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
  v_total := v_subtotal + 100;   -- fixed ₱100 delivery fee, matches the app

  -- Pass 2: create the order (the one-open-order partial unique index
  -- rejects a second concurrent checkout → friendly error).
  BEGIN
    INSERT INTO public.orders (
      customer_id, store_id, status, fulfillment, total_amount,
      payment_method, payment_status, notes, shipping_address, source,
      payment_confirmation_deadline
    ) VALUES (
      auth.uid(), v_first_store, 'awaiting_payment_confirmation', 'pickup',
      v_total, 'gcash', 'pending', p_delivery_address, p_shipping_address,
      'online', now() + interval '30 minutes'
    )
    RETURNING id, payment_confirmation_deadline INTO v_order_id, v_deadline;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.';
  END;

  -- Insert line items → decrement_inventory_on_order fires per row.
  -- Insufficient stock raises P0001 → the WHOLE transaction (order + all
  -- items) rolls back, so no orphaned order and no partial reservation.
  INSERT INTO public.order_items (order_id, product_id, size, quantity, unit_price)
  SELECT v_order_id, product_id, size, quantity, unit_price
    FROM _checkout_items;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (v_order_id, 'created', auth.uid(),
          'Order created, stock reserved, awaiting seller confirmation');

  SELECT name, gcash_qr_url, gcash_number, gcash_account_name
    INTO v_store_name, v_qr, v_number, v_account
    FROM public.stores
   WHERE id = v_first_store;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'store_id', v_first_store,
    'total_amount', v_total,
    'payment_confirmation_deadline', v_deadline,
    'store_name', v_store_name,
    'gcash_qr_url', v_qr,
    'gcash_number', v_number,
    'gcash_account_name', v_account
  );
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 3. submit_gcash_proof (customer, JWT)
--    Validates ownership + state + deadline + reference format, then
--    stores the proof (platform-wide UNIQUE reference number → a single
--    real payment can never confirm two orders) and notifies the seller
--    via the realtime-enabled seller_notifications table (live badge in
--    the seller's Notification Center, which already routes type
--    'new_order' → order detail).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_gcash_proof(
  p_order_id         uuid,
  p_reference_number text,
  p_screenshot_url   text
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
  v_short_id  text;
BEGIN
  SELECT status, store_id, customer_id, payment_confirmation_deadline, total_amount
    INTO v_status, v_store_id, v_customer, v_deadline, v_total
    FROM public.orders
   WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_customer <> auth.uid() THEN
    RAISE EXCEPTION 'You can only submit proof for your own orders';
  END IF;
  IF v_status <> 'awaiting_payment_confirmation' THEN
    RAISE EXCEPTION 'This order is no longer awaiting payment confirmation';
  END IF;
  IF v_deadline IS NOT NULL AND v_deadline < now() THEN
    RAISE EXCEPTION 'The payment confirmation window for this order has expired';
  END IF;
  IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
    RAISE EXCEPTION 'A payment screenshot is required';
  END IF;
  -- The screenshot must live in THIS order's folder ({order_id}/{file},
  -- no leading slash) — prevents attaching another order's screenshot
  -- (which the seller's SELECT policy would block → broken image).
  IF split_part(p_screenshot_url, '/', 1) <> p_order_id::text THEN
    RAISE EXCEPTION 'The screenshot does not match this order';
  END IF;

  -- Normalize to digits-only; GCash refs are 13 digits (12 tolerated —
  -- matches lib/utils/gcash_ref_extractor).
  v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RAISE EXCEPTION 'Enter a valid GCash reference number (12–13 digits)';
  END IF;

  IF EXISTS (SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'A proof has already been submitted for this order';
  END IF;

  BEGIN
    INSERT INTO public.gcash_payment_proofs
      (order_id, reference_number, screenshot_url, submitted_by)
    VALUES (p_order_id, v_ref, p_screenshot_url, auth.uid());
  EXCEPTION WHEN unique_violation THEN
    -- Distinguish the concurrent double-submit race (order_id UNIQUE)
    -- from a genuinely reused reference number (platform-wide UNIQUE).
    IF EXISTS (SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id) THEN
      RAISE EXCEPTION 'A proof has already been submitted for this order';
    END IF;
    RAISE EXCEPTION 'That GCash reference number has already been used for another order';
  END;

  -- Proof submitted → PAUSE the expiry clock (brief §6.3 decision): the
  -- seller now has evidence to verify, so give them a fresh 2-hour window.
  -- Without this, a customer who pays at minute 29 and submits proof could
  -- be expired at minute 30 with their money already sent. The sweep only
  -- expires orders whose deadline has passed, so extending the deadline
  -- is sufficient.
  UPDATE public.orders
     SET payment_confirmation_deadline = now() + interval '2 hours'
   WHERE id = p_order_id;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'proof_submitted', auth.uid(),
          'Reference ' || v_ref || ' submitted');

  -- Seller notification (in-app; realtime pushes the badge live).
  v_short_id := left(p_order_id::text, 8);
  INSERT INTO public.seller_notifications
    (store_id, type, title, body, reference_id)
  VALUES (
    v_store_id, 'new_order',
    'Payment awaiting confirmation',
    'Order #' || v_short_id || ' — ₱' || round(v_total)::text ||
      ' proof submitted. Verify in your GCash app.',
    p_order_id
  );

  RETURN jsonb_build_object('order_id', p_order_id, 'submitted', true);
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 4. confirm_gcash_payment (seller, JWT)
--    Owner-only. Requires a submitted proof. Guarded transition →
--    status='pending' (enters the normal seller pipeline),
--    payment_status='paid', payment_verified_at=now().
--    order_items already exist (reserved at creation) → stock is NOT
--    touched here; it was decremented exactly once, at reservation.
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
  v_updated     int;
  v_short_id    text;
BEGIN
  SELECT s.owner_id, o.customer_id
    INTO v_owner_id, v_customer_id
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

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'confirmed', auth.uid(), 'Payment confirmed by seller');

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

-- ────────────────────────────────────────────────────────────────
-- 5. reject_gcash_payment (seller, JWT)
--    Owner-only. Cancels the order, releases reserved stock (exactly
--    once), logs the event with the seller's reason, and notifies the
--    customer (the reason is visible in-app; disputes use the existing
--    support/report channel + the append-only event log).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_gcash_payment(
  p_order_id uuid,
  p_reason   text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_cancelled boolean;
BEGIN
  SELECT s.owner_id
    INTO v_owner_id
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

  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'cancelled');
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 6. expire_overdue_gcash_orders() — the expiry sweep (idempotent)
--    Cancels + releases every awaiting-payment-confirmation order whose
--    30-minute window has passed, logging 'expired' (actor NULL) and
--    notifying the customer. Safe to call from anywhere at any time:
--    • pg_cron (below) when the extension is usable
--    • opportunistically by the app (checkout return / tracking screen
--      / seller dashboard) — this DB has shown pg_cron may be
--      unavailable, so the app-side trigger is the reliable backstop.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_overdue_gcash_orders()
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
    SELECT id FROM public.orders
     WHERE status = 'awaiting_payment_confirmation'
       AND payment_confirmation_deadline < now()
  LOOP
    IF public.cancel_awaiting_gcash_order(
         v_order,
         'Payment confirmation window expired',
         'The GCash payment was not confirmed within the allowed window. Stock released.',
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
-- 7. Grants — authenticated users may call the five public functions;
--    the private helper stays owner-only (pg_cron runs as the owner).
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_gcash_checkout(jsonb, text, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.submit_gcash_proof(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_gcash_proof(uuid, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.confirm_gcash_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_gcash_payment(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.reject_gcash_payment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_gcash_payment(uuid, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.expire_overdue_gcash_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_overdue_gcash_orders() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.cancel_awaiting_gcash_order(uuid, text, text, text, uuid, boolean) FROM PUBLIC;

-- ────────────────────────────────────────────────────────────────
-- 8. pg_cron job (guarded — same pattern as the PayMongo migration:
--    to_regclass + EXCEPTION so a DB without usable pg_cron never
--    fails this migration; the app calls the sweep opportunistically
--    as the fallback).
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-gcash-confirmations') THEN
    PERFORM cron.schedule(
      'expire-gcash-confirmations',
      '*/5 * * * *',
      $cron$
        SELECT public.expire_overdue_gcash_orders();
      $cron$
    );
    RAISE NOTICE 'Scheduled pg_cron job: expire-gcash-confirmations (every 5 min)';
  ELSE
    RAISE NOTICE 'pg_cron unavailable — expiry enforced by app calls to expire_overdue_gcash_orders().';
  END IF;
EXCEPTION
  WHEN undefined_table OR insufficient_privilege OR undefined_function THEN
    RAISE NOTICE 'pg_cron unavailable — expiry enforced by app calls to expire_overdue_gcash_orders().';
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT proname, prosecdef FROM pg_proc
--   WHERE proname IN ('create_gcash_checkout','submit_gcash_proof',
--                     'confirm_gcash_payment','reject_gcash_payment',
--                     'expire_overdue_gcash_orders','cancel_awaiting_gcash_order')
--   ORDER BY proname;
--
-- SELECT has_function_privilege('authenticated',
--   'public.create_gcash_checkout(jsonb, text, jsonb)', 'EXECUTE');
--
-- SELECT data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'notifications'
--   AND column_name = 'order_id';   -- expect: uuid
--
-- SELECT jobname, schedule FROM cron.job WHERE jobname = 'expire-gcash-confirmations';
