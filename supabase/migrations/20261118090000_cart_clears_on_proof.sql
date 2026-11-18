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
