-- ══════════════════════════════════════════════════════════════════
-- 20261118130000_rejected_payment_refunds.sql
--
-- A 3rd rejection cancels the order — but the customer's money is already in
-- the platform GCash account, and nothing recorded that. `cancel_awaiting_
-- gcash_order` wrote payment_status = 'failed' for every cancellation, which
-- says "no money arrived" about an order whose receipt, reference and amount
-- are sitting in gcash_payment_proofs. The money owed back existed only in the
-- mind of whoever happened to read the rejection.
--
-- This file makes that a fact on the row and a task an admin can work through:
--
--   1. orders.payment_status admits 'refund_pending' and 'refunded'.
--   2. A cancellation sets 'refund_pending' when the order has a proof (money
--      may have moved) and keeps 'failed' when it has none. Data-driven, so
--      the expiry sweep and the customer's own cancel — neither of which can
--      run on an order with a proof — are unaffected.
--   3. admin_list_refund_owed(): the queue, carrying the proof's reference,
--      sender, amount and screenshot path so the refund can be matched to a
--      real GCash transfer.
--   4. admin_mark_refund_refunded(order, reference): closes the task with the
--      GCash reference of the refund, stamps who did it and when, writes the
--      payment-event log and tells the customer their money is back.
--
-- Admin-only, checked inside the functions (is_admin()), so GRANT to
-- authenticated is safe. Nothing here moves money: the transfer is still made
-- by hand in GCash; this is the ledger of what is owed and what was sent.
--
-- Depends on: 20260808230000 (cancel_awaiting_gcash_order),
--             20261118040000 (reject_gcash_proof, the 3-attempt path).
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. The two new payment states
--    refund_pending = the proof was rejected for the last time; the money is
--                     with the platform and an admin owes the customer a
--                     transfer.
--    refunded        = that transfer happened; the reference is on the row.
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  drop constraint if exists orders_payment_status_check;

alter table public.orders
  add constraint orders_payment_status_check
  check (payment_status in
    ('paid', 'unpaid', 'pending', 'failed', 'refund_pending', 'refunded'));

-- ──────────────────────────────────────────────────────────────────
-- 2. The refund's own paper trail
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists refund_reference  text,
  add column if not exists refunded_at       timestamptz,
  add column if not exists refunded_by       uuid
    references public.profiles(id) on delete set null,
  add column if not exists refund_note       text;

comment on column public.orders.refund_reference is
  'GCash reference of the refund CUFMAI sent back to the customer, after a 3rd rejection cancelled an order whose money had already arrived.';
comment on column public.orders.refunded_at is
  'When an admin recorded the refund transfer. NULL while payment_status = refund_pending.';
comment on column public.orders.refunded_by is
  'Admin who sent the refund. Kept for the same reason refunded_at is.';

-- ──────────────────────────────────────────────────────────────────
-- 3. Cancellation records what is owed
--
--    Same function as 20260808230000, with one change: payment_status is no
--    longer hard-coded to 'failed'. An order that has a proof row may have
--    been paid, so cancelling it leaves a debt instead of a failure.
--
--    Everything else is held exactly as it was, because this helper is the
--    single cancellation path for every reason: guarded transition, stock
--    released once, the append-only event, and the recipient guard on the
--    customer notification (a NULL customer must skip the notice, not abort
--    the sweep — see docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md).
-- ──────────────────────────────────────────────────────────────────
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
  r              record;
BEGIN
  -- Money already sent? A proof row is the only evidence the platform has,
  -- and a cancellation only reaches this point after a customer submitted —
  -- or tried to. Read before the UPDATE so the notification can say it too.
  SELECT EXISTS (
    SELECT 1 FROM public.gcash_payment_proofs WHERE order_id = p_order_id
  ) INTO v_refund_owed;

  -- Guarded transition: only transitions an order that is still awaiting.
  -- Row lock serializes concurrent confirm/reject/expiry/cancel.
  UPDATE public.orders
     SET status = 'cancelled',
         payment_status = CASE WHEN v_refund_owed THEN 'refund_pending'
                               ELSE 'failed' END,
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
  -- The RECIPIENT is checked: orders.customer_id is nullable while
  -- notifications.user_id is not, and a NULL here would abort the whole sweep
  -- loop rather than skip one notice.
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

-- ──────────────────────────────────────────────────────────────────
-- 4. The queue: what the platform may owe, with the evidence
-- ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_refund_owed(
  p_include_refunded boolean DEFAULT false
) RETURNS TABLE (
  r_order_id           uuid,
  r_order_code         text,
  r_order_status       text,
  r_payment_status     text,
  r_total              numeric,
  r_cancelled_at       timestamptz,
  r_cancel_reason      text,
  r_store_id           uuid,
  r_store_name         text,
  r_customer_id        uuid,
  r_customer_name      text,
  r_proof_id           uuid,
  r_reference          text,
  r_sender             text,
  r_amount_paid        numeric,
  r_screenshot_path    text,
  r_proof_submitted_at timestamptz,
  r_proof_paid_at      timestamptz,
  r_attempt_no         int,
  r_rejection_reason   text,
  r_refund_reference   text,
  r_refunded_at        timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can see refunds owed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT o.id, o.order_code, o.status::text, o.payment_status::text,
           o.total_amount, o.cancelled_at, o.cancellation_reason,
           s.id, s.name, o.customer_id, c.full_name,
           pr.id, pr.reference_number, pr.sender_name, pr.amount_paid,
           pr.screenshot_url, pr.submitted_at, pr.paid_at, pr.attempt_no,
           pr.rejection_reason,
           o.refund_reference, o.refunded_at
      FROM public.orders o
      JOIN public.stores s ON s.id = o.store_id
      LEFT JOIN public.profiles c ON c.id = o.customer_id
      -- The LAST attempt is the one whose rejection cancelled the order, so
      -- that is the reference an admin must match in the GCash statement.
      LEFT JOIN LATERAL (
        SELECT gp.*
          FROM public.gcash_payment_proofs gp
         WHERE gp.order_id = o.id
         ORDER BY gp.attempt_no DESC
         LIMIT 1
      ) pr ON true
     WHERE o.payment_status = 'refund_pending'
        OR (p_include_refunded AND o.payment_status = 'refunded')
     ORDER BY COALESCE(o.cancelled_at, o.created_at) DESC;
END;
$$;

-- ──────────────────────────────────────────────────────────────────
-- 5. Closing the task
--    Takes the GCash reference of the transfer: without it the row would claim
--    a refund nobody can trace, which is the same gap one step later.
-- ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_mark_refund_refunded(
  p_order_id  uuid,
  p_reference text,
  p_notes     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reference text;
  v_notes     text;
  v_customer  uuid;
  v_amount    numeric;
  v_short_id  text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can record a refund'
      USING ERRCODE = '42501';
  END IF;

  v_reference := btrim(COALESCE(p_reference, ''));
  IF length(v_reference) < 4 THEN
    RAISE EXCEPTION 'Record the GCash reference of the refund';
  END IF;
  v_notes := NULLIF(btrim(COALESCE(p_notes, '')), '');

  UPDATE public.orders
     SET payment_status = 'refunded',
         refund_reference = v_reference,
         refunded_at = now(),
         refunded_by = auth.uid(),
         refund_note = v_notes
   WHERE id = p_order_id
     AND payment_status = 'refund_pending'
   RETURNING customer_id, total_amount INTO v_customer, v_amount;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That order is not waiting for a refund';
  END IF;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (p_order_id, 'refunded', auth.uid(),
          'Refund sent manually: ' || v_reference ||
          COALESCE(' — ' || v_notes, ''));

  IF v_customer IS NOT NULL THEN
    v_short_id := left(p_order_id::text, 8);
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_customer,
      p_order_id,
      'returns',
      'Refund sent',
      'Order #' || v_short_id || ' — CUFMAI sent ₱' ||
        to_char(COALESCE(v_amount, 0), 'FM999999990.00') ||
        ' back to your GCash (ref ' || v_reference || ').'
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'payment_status', 'refunded',
    'reference', v_reference
  );
END;
$$;

-- ──────────────────────────────────────────────────────────────────
-- 6. The event type the closing step writes
--
--    Re-stated as the FULL list, not this file's addition alone: the v2
--    lifecycle types from 20261118030000 (resubmitted, seller_verified,
--    admin_verified, flagged, unflagged, funds_reconciled) are written by
--    submit_gcash_proof and the admin RPCs on ordinary days, and a CHECK that
--    forgot them would fail the second proof attempt, not the refund one.
-- ──────────────────────────────────────────────────────────────────
ALTER TABLE public.order_payment_events
  DROP CONSTRAINT IF EXISTS order_payment_events_event_type_check;

ALTER TABLE public.order_payment_events
  ADD CONSTRAINT order_payment_events_event_type_check
  CHECK (event_type IN
    ('created', 'proof_submitted', 'confirmed', 'rejected', 'expired',
     'cancelled_by_customer',
     'resubmitted', 'seller_verified', 'admin_verified',
     'flagged', 'unflagged', 'funds_reconciled',
     'refunded'));

COMMENT ON TABLE public.order_payment_events IS
  'Append-only payment lifecycle log. event_type: created / proof_submitted / confirmed / rejected / expired / cancelled_by_customer / resubmitted / seller_verified / admin_verified / flagged / unflagged / funds_reconciled / refunded. actor_id = the user who acted (NULL for the automated expiry sweep). Written only by SECURITY DEFINER RPCs.';

-- ──────────────────────────────────────────────────────────────────
-- 7. Grants — admin-gated inside, so authenticated may call
-- ──────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.admin_list_refund_owed(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_refund_owed(boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_mark_refund_refunded(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_refund_refunded(uuid, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_awaiting_gcash_order(uuid, text, text, text, uuid, boolean)
  FROM PUBLIC, anon, authenticated;

commit;
