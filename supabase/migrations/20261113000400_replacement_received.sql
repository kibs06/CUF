-- ══════════════════════════════════════════════════════════════════
-- `replacement_received` — the customer closes a shipped replacement
-- Date: 2026-11-12
--
-- `replaced` means "the seller approved the return and owes a
-- replacement". For an in-store swap that is the end of it — the pair
-- changes hands over the counter. For a shipped replacement it is only
-- the beginning: the parcel still has to travel, and until now nothing
-- could mark it done, so a replacement delivered last week looked
-- exactly like one still sitting on the bench.
--
-- This mirrors the main order lifecycle (delivered → customer confirms
-- → received) one step later:
--
--     delivered → received            (confirm the purchase arrived)
--     replaced  → replacement_received (confirm the replacement arrived)
--
-- Customer-driven, so it is a SECURITY DEFINER RPC rather than a wider
-- UPDATE policy: `orders` carries `total_amount`, `payment_status` and
-- `store_id`, and RLS cannot say "status column only" (the reason
-- `cancel_my_order` and `request_my_return` are functions too). The
-- status change fires `trg_record_order_status_change`, so the timeline
-- row comes for free.
--
-- Confirmation notifies both sides in the same transaction — a customer
-- feed row (`notifications`, the same shape the request and approval
-- write) and a store row (`seller_notifications`). The seller's device
-- push is the customer app's job, exactly like `notifyReturnRequested`:
-- the server owns the in-app rows, the app owns FCM.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Status CHECK: add `replacement_received` ────────────────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN (
      'pending', 'placed', 'preparing', 'ready', 'delivered',
      'received', 'cancelled', 'cancellation_requested',
      'awaiting_payment', 'payment_conflict',
      'awaiting_payment_confirmation',
      'return_requested', 'replaced', 'replacement_received', 'refunded'
    ));

-- ── 2. When the customer confirmed ────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS replacement_received_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.replacement_received_at IS
  'When the customer confirmed the shipped replacement arrived (status moves replaced → replacement_received). NULL for an in-store swap, which is finished at the counter.';

-- ── 3. Seller bell: admit the new notification type ─────────────
-- `seller_notifications.type` is CHECK-constrained, and an unlisted type
-- is a 23514 that would abort the whole confirmation below. The current
-- list is the one from 20261111120000_review_comments.sql, plus this one.
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
        'replacement_received'
      )
    );

-- ── 4. RPC: customer confirms the replacement arrived ─────────────
CREATE OR REPLACE FUNCTION public.confirm_replacement_received(
  p_order_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order    public.orders%ROWTYPE;
  v_store_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  -- Row lock: a double tap cannot confirm twice.
  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  -- One message for "no such order" and "not yours", so the function
  -- cannot be used to probe order ids.
  IF v_order.id IS NULL OR v_order.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Order not found'
      USING ERRCODE = '42501';
  END IF;

  IF v_order.status = 'replacement_received' THEN
    RAISE EXCEPTION 'You have already confirmed this replacement.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_order.status <> 'replaced' THEN
    RAISE EXCEPTION
      'There is no replacement waiting to be confirmed on this order.'
      USING ERRCODE = 'P0001';
  END IF;

  -- An in-store swap was handed over at the counter: already done. The
  -- app hides the button for it, this is the server-side half of that
  -- rule. (NULL method = approved before the path was recorded, so the
  -- customer is allowed to close it.)
  IF v_order.replacement_method = 'in_store' THEN
    RAISE EXCEPTION
      'This replacement was handed over in store — there is nothing left to confirm.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
     SET status                  = 'replacement_received',
         replacement_received_at = now()
   WHERE id = p_order_id;

  -- Customer feed: every other step of this flow lands here (the request,
  -- the approval), so the confirmation does too — the order's own history
  -- in the app, next to the push-less record of what happened when.
  -- `orders.customer_id` is nullable, and a NULL recipient turns a skipped
  -- notification into a failed transaction (repo recipient rule).
  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_order.customer_id,
      p_order_id,
      'returns',
      'Replacement received',
      'Order #' || left(p_order_id::text, 8) ||
        ' — thanks for confirming. This return is now closed.'
    );
  END IF;

  -- Seller bell: the store needs to know the swap is closed out (it is
  -- the seller side's "done", exactly like `received` on a normal order).
  -- NULL store_id (custom/legacy orders) would 23502-abort the whole
  -- confirmation, so it is guarded — the repo's recipient rule.
  v_store_id := v_order.store_id;
  IF v_store_id IS NOT NULL THEN
    INSERT INTO public.seller_notifications (store_id, type, title, body, reference_id)
    VALUES (
      v_store_id,
      'replacement_received',
      'Replacement received',
      'Order #' || left(p_order_id::text, 8) ||
        ' — the customer confirmed they received the replacement.',
      p_order_id
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'status',   'replacement_received'
  );
END;
$$;

-- `REVOKE ... FROM PUBLIC` alone is not enough in this project: Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` by name.
REVOKE EXECUTE ON FUNCTION public.confirm_replacement_received(uuid)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.confirm_replacement_received(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.confirm_replacement_received(uuid) IS
  'Customer confirms a shipped replacement arrived: replaced -> replacement_received, stamps replacement_received_at, writes a customer feed row and the store''s seller-bell row. Own orders only; in-store swaps are already finished.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- 1. Grants — anon must be false, authenticated true:
--
--    SELECT has_function_privilege('anon',
--             'public.confirm_replacement_received(uuid)', 'EXECUTE') AS anon_may,
--           has_function_privilege('authenticated',
--             'public.confirm_replacement_received(uuid)', 'EXECUTE') AS auth_may;
--
-- 2. Unknown / foreign orders must both answer 'Order not found' (42501):
--
--    SELECT public.confirm_replacement_received(gen_random_uuid());
--
-- 3. A non-'replaced' order must be rejected (expect P0001):
--
--    SELECT public.confirm_replacement_received('<received order id>');
--
-- 4. Happy path — as the order's own customer, on a shipped replacement.
--    Both feeds must gain a row, and the second call must be rejected:
--
--    BEGIN;
--      SELECT public.confirm_replacement_received('<own replaced order id>');
--      SELECT status, replacement_received_at FROM public.orders
--       WHERE id = '<own replaced order id>';
--      SELECT category, title FROM public.notifications
--       WHERE order_id = '<own replaced order id>'
--       ORDER BY created_at DESC LIMIT 1;          -- returns | Replacement received
--      SELECT type, title FROM public.seller_notifications
--       WHERE reference_id = '<own replaced order id>'
--       ORDER BY created_at DESC LIMIT 1;          -- replacement_received
--      SELECT public.confirm_replacement_received('<own replaced order id>');
--      ROLLBACK;
