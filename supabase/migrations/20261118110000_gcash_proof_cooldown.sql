-- ════════════════════════════════════════════════════════════════════
-- One GCash proof file per minute, per customer
--
-- The uniqueness indexes already stop the harmful duplicates: the same
-- reference, the same screenshot, one pending proof per order, one attempt
-- number per order. They say nothing about a customer who files attempt
-- after attempt with fresh material — each one becomes a seller notification,
-- an admin bell, an order_payment_events row and a review somebody has to
-- read. That is persistence, not duplication, and no index can refuse it.
--
-- So the RPC carries a cooldown: if this customer filed any proof within the
-- last 60 seconds, the submission is refused before a row is written and the
-- message says how long is left. The clock is submitted_at, which
-- trg_pin_gcash_proof_time stamps from the server and pins on update, so a
-- client cannot wait out its own cooldown by editing the row.
--
-- 60 seconds is deliberately short: the proof goes to a human for review, so
-- a real customer has no reason to file twice inside a minute, while a legit
-- correction after a mistyped reference costs one minute, not a lockout.
-- Follows the existing attempt rules rather than replacing them — the 3-attempt
-- cap and the one-pending-proof index still decide how many attempts an order
-- may have.
--
-- The window is a platform setting, not a constant in the function, because the
-- right number belongs to the operator (a busy store may want 30s) and because
-- the suites that are about OTHER rules file several proofs in a row and would
-- otherwise be testing this clock instead of their own subject. 0 disables it.
--
-- Depends on: 20261118090000 (the function replaced here, which added the cart
-- cleanup call) and 20261118070000 (the proof-time trigger). Body otherwise
-- identical to 20261118090000; signature unchanged, so the grants set by
-- 20261118040000 still apply.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE public.platform_settings
  ADD COLUMN IF NOT EXISTS gcash_proof_cooldown_seconds int NOT NULL DEFAULT 60;

ALTER TABLE public.platform_settings
  DROP CONSTRAINT IF EXISTS platform_settings_gcash_proof_cooldown_check;
ALTER TABLE public.platform_settings
  ADD CONSTRAINT platform_settings_gcash_proof_cooldown_check
  CHECK (gcash_proof_cooldown_seconds BETWEEN 0 AND 3600);

COMMENT ON COLUMN public.platform_settings.gcash_proof_cooldown_seconds IS
  'Minimum seconds between two GCash proof files from the same customer. 0 disables the cooldown. Enforced inside submit_gcash_proof against the server-stamped submitted_at, so it cannot be waited out from the client.';

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
  c_default_cooldown constant int := 60;
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
  v_last_file timestamptz;
  v_wait      int;
  v_cooldown  int;
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

  -- ── Per-customer cooldown ────────────────────────────────────────
  -- Checked after the order's own state, so a customer who already filed for
  -- THIS order is told that (a more useful sentence) rather than the clock.
  -- Across every order the customer owns: filing for a second order is still
  -- filing, and the seller and admin bells ring the same way.
  SELECT COALESCE(max(s.gcash_proof_cooldown_seconds), c_default_cooldown)
    INTO v_cooldown
    FROM public.platform_settings s
   WHERE s.id = 1;

  IF COALESCE(v_cooldown, c_default_cooldown) > 0 THEN
    v_cooldown := COALESCE(v_cooldown, c_default_cooldown);
    SELECT max(pr.submitted_at) INTO v_last_file
      FROM public.gcash_payment_proofs pr
      JOIN public.orders o ON o.id = pr.order_id
     WHERE o.customer_id = v_customer;

    IF v_last_file IS NOT NULL
       AND v_last_file > now() - make_interval(secs => v_cooldown) THEN
      v_wait := GREATEST(
        1,
        CEIL(EXTRACT(EPOCH FROM
          (v_last_file + make_interval(secs => v_cooldown) - now())))::int
      );
      RAISE EXCEPTION 'You just filed a GCash proof. Try again in % second(s).',
        v_wait;
    END IF;
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
