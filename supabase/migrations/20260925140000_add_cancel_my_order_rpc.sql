-- ══════════════════════════════════════════════════════════════════
-- Migration: cancel_my_order — customer self-service cancellation
-- Date: 2026-09-25
--
-- ── Why this has to be a function ─────────────────────────────────
-- The app cancels an order by UPDATE-ing `orders` from the customer's
-- own client (`OrderProvider.cancelOrder` → `SupabaseService.
-- updateOrderStatus`). Measured against the deployed database on
-- 2026-09-25, that cannot work: **`orders` has no customer UPDATE
-- policy.** The only two UPDATE policies are
--
--     "Sellers can update their own store's orders"   (own store only)
--     "Admins can update all orders"                  (is_admin())
--
-- so a customer's UPDATE matches zero rows. RLS does not raise — the
-- statement SUCCEEDS and reports 0 rows — which is why this failure is
-- invisible in the app instead of loud: `cancelOrder` awaits an update
-- with no `.select()`, receives no exception, and returns true. The
-- screen then shows a snackbar saying the order was cancelled while the
-- order is untouched.
--
--     PATCH /rest/v1/orders?id=eq.<own order>   {"status":"cancelled"}
--     → 200, []          (the row exists; the policy filtered it out)
--
-- The second half of that same call is worse than a no-op. The
-- `order_status_history` INSERT policy is
-- `WITH CHECK (auth.uid() IS NOT NULL)` — an ownership check is missing
-- entirely — so the app writes a "cancelled" timeline row for an order
-- it did not manage to cancel, and ANY signed-in user can forge status
-- history onto ANY order, including another store's. Verified the same
-- way: a POST carrying only an order_id and a status returned 201.
--
-- ── Why not widen the UPDATE policy ───────────────────────────────
-- Because an UPDATE policy is whole-row: granting it on
-- `auth.uid() = customer_id` would let a customer set `total_amount`,
-- `payment_status` or `store_id` on their own order, i.e. hand the
-- client the two columns every RPC in this schema exists to protect.
-- RLS cannot express "only these columns, only these transitions"
-- (WITH CHECK sees NEW but not OLD), so the honest place for the rule is
-- a SECURITY DEFINER function — the shape this schema already uses for
-- every other customer-initiated mutation (`cancel_my_pending_gcash_
-- checkout`, `cancel_my_pending_payment_intent`, `cancel_pickup_
-- reservation`).
--
-- ── What the function does NOT do ─────────────────────────────────
-- It does not touch `inventory`. Nothing in this database releases stock
-- when an order is cancelled: the seller app's cancel is the same bare
-- UPDATE, and `cancel_awaiting_gcash_order` — the one place that does
-- add stock back — exists only for orders whose stock was RESERVED at
-- creation and never sold. A paid order's stock is decremented by
-- `decrement_inventory_on_order` when its `order_items` are materialized
-- after payment, and no path gives it back. Making the web portal the
-- only surface that does would desync it from the seller dashboard and
-- double-count whenever a maker had already restocked a cancelled pair
-- by hand, so it is left alone deliberately — see the note at the foot
-- of this file for the right place to fix it.
--
-- It also does not delete `order_items`: those rows are the record of
-- what was bought, and unlike the reservation flow above they must
-- survive the cancellation.
--
-- ── Reuses what already works ─────────────────────────────────────
-- The UPDATE fires two existing triggers, so no bookkeeping is
-- duplicated here: `trg_record_order_status_change` writes the
-- `order_status_history` row a customer can read back, and
-- `trg_notify_on_order_status_change` — which maps 'cancelled' to "no
-- notification" — is why an explicit notification is inserted below.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cancel_my_order(
  p_order_id uuid,
  p_reason   text,
  p_details  text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_new   text;
  v_since timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Choose a reason for cancelling this order'
      USING ERRCODE = 'P0001';
  END IF;

  -- Free text is required for 'Other', the same rule the app's reason
  -- sheet enforces (the predefined list is expected to be reused for
  -- reporting, so a stray 'Other' with no detail is a lost signal).
  IF p_reason = 'Other' AND (p_details IS NULL OR btrim(p_details) = '') THEN
    RAISE EXCEPTION 'Tell us a little more, so the maker knows what happened'
      USING ERRCODE = 'P0001';
  END IF;

  -- Row lock: serializes this against a seller confirming the order at
  -- the same instant, so the two cannot both win.
  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  -- One message for "no such order" and "not yours", so the function
  -- cannot be used to probe which order ids exist.
  IF v_order.id IS NULL OR v_order.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Order not found'
      USING ERRCODE = '42501';
  END IF;

  -- ── Which transition this is ──────────────────────────────────────
  -- Mirrors `TrackingScreen._canCancel` exactly: pending / placed cancel
  -- outright, preparing becomes a REQUEST the maker approves. 'ready' is
  -- deliberately not cancellable — the pair is already bagged and
  -- waiting — which is the same rule the app's action button encodes
  -- ('ready' shows "Track", not "Cancel").
  IF v_order.status IN ('pending', 'placed') THEN
    v_new := 'cancelled';

  ELSIF v_order.status = 'preparing' THEN
    -- `AppConstants.processingCancelWindowHours` = 2, measured from the
    -- order's own history rather than from `created_at`, because a maker
    -- can take days to confirm. An order with no 'preparing' row
    -- predates the history trigger; unknown age is allowed through,
    -- since this transition is a request and not a unilateral cancel.
    SELECT max(changed_at) INTO v_since
      FROM public.order_status_history
     WHERE order_id = p_order_id
       AND status = 'preparing';

    IF v_since IS NOT NULL AND v_since < now() - interval '2 hours' THEN
      RAISE EXCEPTION
        'The maker has already started this order and the 2-hour cancellation window has closed. Message the store to arrange a return.'
        USING ERRCODE = 'P0001';
    END IF;
    v_new := 'cancellation_requested';

  ELSIF v_order.status = 'cancellation_requested' THEN
    RAISE EXCEPTION
      'You have already asked to cancel this order — the maker will respond shortly.'
      USING ERRCODE = 'P0001';

  ELSIF v_order.status IN ('awaiting_payment', 'awaiting_payment_confirmation') THEN
    -- The unpaid branches have their own cancel RPCs, which also release
    -- the stock reservation. Sending the customer there keeps one owner
    -- per transition instead of two functions racing on one order.
    RAISE EXCEPTION
      'This order is still waiting for payment. Cancel it from the payment screen instead.'
      USING ERRCODE = 'P0001';

  ELSIF v_order.status = 'payment_conflict' THEN
    RAISE EXCEPTION
      'This order needs a person to check it against the payment — please contact the store.'
      USING ERRCODE = 'P0001';

  ELSE
    -- ready / delivered / received
    RAISE EXCEPTION
      'A % order can no longer be cancelled here. Contact the store for a return.',
      v_order.status
      USING ERRCODE = 'P0001';
  END IF;

  -- The history row and the notification trigger both hang off this
  -- UPDATE. `cancelled_at` is set only for a terminal cancel: a request
  -- is not a cancellation yet, and stamping it as one would tell the
  -- seller dashboard a pair was released when it is still on the bench.
  UPDATE public.orders
     SET status               = v_new,
         cancellation_reason  = p_reason,
         cancellation_details = nullif(btrim(coalesce(p_details, '')), ''),
         cancelled_at         = CASE
                                  WHEN v_new = 'cancelled' THEN now()
                                  ELSE cancelled_at
                                END
   WHERE id = p_order_id;

  -- `notify_on_order_status_change` returns early for 'cancelled' and
  -- has no mapping for 'cancellation_requested', so the customer is told
  -- here. Recipient is guarded for the reason
  -- docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md sets out: `notifications.
  -- user_id` is NOT NULL, and an unguarded NULL turns a skipped
  -- notification into a failed transaction.
  IF v_order.customer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      v_order.customer_id,
      p_order_id,
      'returns',
      CASE WHEN v_new = 'cancelled'
           THEN 'Order cancelled'
           ELSE 'Cancellation requested' END,
      -- First 8 chars, matching `cancel_awaiting_gcash_order` and, more to
      -- the point, the reference the customer portal already prints on its
      -- checkout and payment pages. (`notify_on_order_status_change` uses the
      -- LAST 8 — the schema carries both conventions, and the one the
      -- customer reads on the website wins for a message they read next to
      -- it.)
      'Order #' || left(p_order_id::text, 8) || ' — ' ||
      CASE WHEN v_new = 'cancelled'
           THEN 'You cancelled this order. Reason: ' || p_reason
           ELSE 'Waiting for the maker to confirm your cancellation.' END
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id',  p_order_id,
    'status',    v_new,
    'requested', v_new = 'cancellation_requested'
  );
END;
$$;

-- `REVOKE ... FROM PUBLIC` alone is not enough in this project: Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` by name, which a
-- PUBLIC revoke does not touch (the same hole
-- `20260925120000_revoke_anon_on_deprecated_gcash_rpcs.sql` closed on the
-- deprecated GCash functions). Both roles are named explicitly.
REVOKE EXECUTE ON FUNCTION public.cancel_my_order(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancel_my_order(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.cancel_my_order(uuid, text, text) IS
  'Customer self-service order cancellation. pending/placed -> cancelled; preparing -> cancellation_requested, only within 2 hours of entering preparing. Own orders only. Does not release inventory: no path in this schema does for a paid order.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- 1. Grants — anon must be false (expect f, t):
--
--    SELECT has_function_privilege('anon',
--             'public.cancel_my_order(uuid, text, text)', 'EXECUTE') AS anon_may,
--           has_function_privilege('authenticated',
--             'public.cancel_my_order(uuid, text, text)', 'EXECUTE') AS auth_may;
--
-- 2. Unknown / foreign orders must both answer 'Order not found' with
--    ERRCODE 42501 — i.e. the function cannot be used to probe ids:
--
--    SELECT public.cancel_my_order(gen_random_uuid(), 'Changed my mind');
--
-- 3. An 'Other' reason with no detail must be rejected (expect P0001):
--
--    SELECT public.cancel_my_order('<a real pending order id>', 'Other');
--
-- 4. The happy path, against one of your own pending orders. This WRITES
--    (status + a history row + a notification), so run it on a throwaway
--    order or roll it back:
--
--    BEGIN;
--      SELECT public.cancel_my_order('<own pending order id>',
--                                    'Changed my mind', NULL);
--      ROLLBACK;
--
-- ══════════════════════════════════════════════════════════════════
-- OPEN ITEM — inventory on cancellation
-- ══════════════════════════════════════════════════════════════════
-- Cancelling a PAID order does not return the pair to `inventory`. That
-- is this project's existing behaviour on every path (seller app, POS,
-- admin), not a new gap introduced here — but it is a real one, and a
-- storefront that can cancel a paid order makes it easy to hit. The
-- right fix is an AFTER UPDATE OF status trigger on `orders` that adds
-- `order_items.quantity` back on entry to 'cancelled', so every surface
-- gains it at once and none of them can disagree. It needs a decision
-- first: restocking immediately is wrong for a delivery that has already
-- left the bench, and there is no 'returned to stock' column to
-- distinguish the two cases.
-- ══════════════════════════════════════════════════════════════════
