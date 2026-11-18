-- ════════════════════════════════════════════════════════════════════
-- One GCash proof file per minute — now across both proof families
--
-- 20261118110000 put the cooldown in submit_gcash_proof. The bulk
-- reservation deposit RPC, submit_bulk_reservation_deposit_proof, has the
-- same shape and the same hole: its unique indexes stop a reused reference
-- and a second proof for one reservation, and nothing stops a customer
-- filing attempts for reservation after reservation with fresh material.
--
-- Rather than grow a second copy of the same rule (two clocks that can drift,
-- and a customer who can alternate between families to double their rate),
-- the window now lives in one helper, public.gcash_proof_cooldown_remaining(),
-- which reads the newest file of EITHER kind for that customer. Both RPCs call
-- it. It takes a customer id, so it is not a client RPC.
--
-- Unchanged on purpose:
--   • the window still comes from platform_settings.gcash_proof_cooldown_seconds
--     (default 60, 0 disables, admin-only write);
--   • the clock is still the server's submitted_at, which nothing client-side
--     can move (order proofs are pinned by trg_pin_gcash_proof_time; deposits
--     are stamped by the column default inside the RPC, which never accepts a
--     client time);
--   • each RPC keeps its own error voice — the order flow raises a sentence
--     with the seconds left, the deposit flow raises the short code
--     'PROOF_COOLDOWN' that lib/services/reservation_service.dart already
--     translates for the customer;
--   • every other rule in both functions is byte-identical to the versions
--     they replace (20261118110000 and 20260913140000).
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. The one rule: seconds left before this customer may file again
--    (0 = may file now).
--
--    Not callable by clients: it takes a customer id, so exposing it would
--    let anyone probe another customer's activity timing.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gcash_proof_cooldown_remaining(
  p_customer uuid
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_default_cooldown constant int := 60;
  v_cooldown int;
  v_last     timestamptz;
BEGIN
  IF p_customer IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(s.gcash_proof_cooldown_seconds, c_default_cooldown)
    INTO v_cooldown
    FROM public.platform_settings s
   WHERE s.id = 1;

  v_cooldown := COALESCE(v_cooldown, c_default_cooldown);
  IF v_cooldown <= 0 THEN
    RETURN 0;
  END IF;

  -- The newest file of either kind. GREATEST ignores NULLs, which is what we
  -- want: a customer with only order proofs, or only deposits, still works.
  SELECT GREATEST(
           (SELECT max(pr.submitted_at)
              FROM public.gcash_payment_proofs pr
              JOIN public.orders o ON o.id = pr.order_id
             WHERE o.customer_id = p_customer),
           (SELECT max(d.submitted_at)
              FROM public.bulk_reservation_deposits d
             WHERE d.submitted_by = p_customer)
         )
    INTO v_last;

  IF v_last IS NULL OR v_last <= now() - make_interval(secs => v_cooldown) THEN
    RETURN 0;
  END IF;

  RETURN GREATEST(
    1,
    CEIL(EXTRACT(EPOCH FROM
      (v_last + make_interval(secs => v_cooldown) - now())))::int
  );
END;
$$;

COMMENT ON FUNCTION public.gcash_proof_cooldown_remaining(uuid) IS
  'Seconds a customer must still wait before filing another GCash proof — order proof or bulk reservation deposit, whichever they filed last. 0 means they may file now. The window comes from platform_settings.gcash_proof_cooldown_seconds and the clock from the server-stamped submitted_at.';

REVOKE ALL ON FUNCTION public.gcash_proof_cooldown_remaining(uuid)
  FROM PUBLIC, anon, authenticated;

-- ────────────────────────────────────────────────────────────────
-- 2. submit_gcash_proof — the inline window from 20261118110000 replaced by
--    the shared helper, so it now also respects a deposit filed a moment ago.
--    Everything else is unchanged.
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
  v_wait      int;
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

  -- Per-customer cooldown, shared with the bulk deposit flow.
  v_wait := public.gcash_proof_cooldown_remaining(v_customer);
  IF v_wait > 0 THEN
    RAISE EXCEPTION 'You just filed a GCash proof. Try again in % second(s).',
      v_wait;
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

-- ────────────────────────────────────────────────────────────────
-- 3. submit_bulk_reservation_deposit_proof — cooldown added after the
--    reservation's own state and deadline, before anything is written.
--    Raises the short code the app already translates. Every other rule
--    (ownership, status, deadline, folder, 12–13 digits, cross-family
--    reference dedupe, one-proof-per-reservation, seller notification) is
--    copied unchanged from 20260913140000.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_bulk_reservation_deposit_proof(
    p_reservation_id   UUID,
    p_reference_number TEXT,
    p_screenshot_url   TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_customer UUID := auth.uid();
    v_store_owner UUID;
    v_ref TEXT;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize vs confirm/reject/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'awaiting_deposit' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;
    IF v_reservation.deposit_deadline IS NOT NULL
       AND v_reservation.deposit_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'DEPOSIT_DEADLINE_PASSED';
    END IF;

    -- Per-customer cooldown, shared with the order proof flow. A short code
    -- rather than a sentence because this RPC's errors are translated by
    -- friendlyReservationError() in lib/services/reservation_service.dart.
    IF public.gcash_proof_cooldown_remaining(v_customer) > 0 THEN
        RAISE EXCEPTION 'PROOF_COOLDOWN';
    END IF;

    IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;
    -- The screenshot must live in THIS reservation's folder
    -- ({reservation_id}/{file}) — same anti-mixing rule as order proofs.
    IF split_part(p_screenshot_url, '/', 1) <> p_reservation_id::text THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;

    -- Normalize to digits-only; GCash refs are 13 digits (12 tolerated —
    -- matches lib/utils/gcash_ref_extractor and the order-flow rule).
    v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
    IF length(v_ref) NOT IN (12, 13) THEN
        RAISE EXCEPTION 'INVALID_PROOF_REFERENCE';
    END IF;

    -- Platform-wide dedupe ACROSS proof families: a reference already
    -- used for an order proof cannot confirm a deposit too. (The reverse
    -- direction — the dormant order flow checking deposits — is not
    -- added; the order flow is legacy and out of scope here.) Guarded on
    -- to_regclass so the migration is safe even where the dormant
    -- order-proof table was never created.
    IF to_regclass('public.gcash_payment_proofs') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.gcash_payment_proofs
                   WHERE reference_number = v_ref) THEN
            RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.bulk_reservation_deposits
            (reservation_id, reference_number, screenshot_url, submitted_by)
        VALUES (p_reservation_id, v_ref, p_screenshot_url, v_customer);
    EXCEPTION WHEN unique_violation THEN
        -- Distinguish the concurrent double-submit race (reservation_id
        -- UNIQUE) from a genuinely reused reference (platform UNIQUE).
        IF EXISTS (SELECT 1 FROM public.bulk_reservation_deposits
                   WHERE reservation_id = p_reservation_id) THEN
            RAISE EXCEPTION 'DEPOSIT_ALREADY_SUBMITTED';
        END IF;
        RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
    END;

    -- Notify the seller that a proof awaits verification.
    SELECT s.owner_id INTO v_store_owner
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    IF v_store_owner IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_store_owner, 'reservations',
            'Deposit proof submitted',
            'A customer submitted a GCash deposit proof (₱' ||
            COALESCE(v_reservation.deposit_amount, 0)::int || ', ref ' ||
            v_ref || ') for their ' || v_reservation.quantity ||
            '-unit reservation. Verify it in your GCash app and confirm to hold the stock.'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_bulk_reservation_deposit_proof FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_bulk_reservation_deposit_proof TO authenticated;
