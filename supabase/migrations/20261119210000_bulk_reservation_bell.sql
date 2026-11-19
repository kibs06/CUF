-- 20261119210000_bulk_reservation_bell.sql
--
-- A bulk reservation had a push and a row in the per-user `notifications`
-- table, but no row in `seller_notifications` — the table the seller's
-- Notification Center (the bell) actually reads. Dismiss the push and the
-- request was gone from the bell entirely.
--
-- Two triggers, one per event the seller must be able to find again:
--   • a new request      → AFTER INSERT on bulk_reservations (status pending)
--   • a deposit proof    → AFTER INSERT on bulk_reservation_deposits
--
-- Triggers rather than another edit to the RPCs: the reservation RPCs are long
-- and security-sensitive (they are the stock gate), and a trigger writes the
-- bell row in the same transaction without touching that logic. The per-user
-- `notifications` insert stays where it is — the bell is additive, and a seller
-- who reads only one of the two surfaces still learns about the request.
--
-- NOT APPLIED to the hosted project. Apply with:
--   supabase db push

-- ── 1. The bell's type vocabulary ───────────────────────────────────
-- Restated in full because a CHECK cannot be extended in place. Includes
-- 'payout' from 20261119200000 so applying these in order never narrows the
-- list again.
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
        'permit_expiring',
        'payout',
        'bulk_reservation',
        'bulk_reservation_deposit'
      )
    );

-- ── 2. A new reservation request ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_seller_bulk_reservation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- The bell is keyed by STORE and `bulk_reservations.store_id` is part of the
  -- request, but it is read into a local first: a NULL recipient would be a
  -- 23502 that rolls back the CUSTOMER's request, not just the notice.
  v_store_id uuid;
  v_product text;
BEGIN
  v_store_id := NEW.store_id;
  IF v_store_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT p.name INTO v_product
    FROM public.products p
   WHERE p.id = NEW.product_id;

  INSERT INTO public.seller_notifications
    (store_id, type, title, body, reference_id)
  VALUES (
    v_store_id,
    'bulk_reservation',
    'New bulk reservation request',
    'A customer requested ' || NEW.quantity || ' units of ' ||
      COALESCE(v_product, 'a product') ||
      ' for resale. Approve or decline it in Bulk Reservations.',
    NEW.id
  );

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_seller_bulk_reservation
  ON public.bulk_reservations;
CREATE TRIGGER trg_notify_seller_bulk_reservation
  AFTER INSERT ON public.bulk_reservations
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION public.notify_seller_bulk_reservation();

-- ── 3. The customer's deposit proof ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_seller_bulk_deposit_proof()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation public.bulk_reservations%ROWTYPE;
  v_store_id uuid;
BEGIN
  SELECT * INTO v_reservation
    FROM public.bulk_reservations
   WHERE id = NEW.reservation_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_store_id := v_reservation.store_id;
  IF v_store_id IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.seller_notifications
    (store_id, type, title, body, reference_id)
  VALUES (
    v_store_id,
    'bulk_reservation_deposit',
    'Deposit proof submitted',
    'A customer sent a GCash deposit proof (₱' ||
      COALESCE(v_reservation.deposit_amount, 0)::int || ', ref ' ||
      NEW.reference_number || ') for their ' || v_reservation.quantity ||
      '-unit reservation. Verify it in your GCash app, then confirm to hold '
      'the stock.',
    v_reservation.id
  );

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_seller_bulk_deposit_proof
  ON public.bulk_reservation_deposits;
CREATE TRIGGER trg_notify_seller_bulk_deposit_proof
  AFTER INSERT ON public.bulk_reservation_deposits
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_seller_bulk_deposit_proof();

COMMENT ON FUNCTION public.notify_seller_bulk_reservation() IS
  'Writes the seller''s bell row for a new bulk reservation request.';
COMMENT ON FUNCTION public.notify_seller_bulk_deposit_proof() IS
  'Writes the seller''s bell row when a customer submits a deposit proof.';
