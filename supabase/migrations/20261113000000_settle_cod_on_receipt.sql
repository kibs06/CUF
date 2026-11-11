-- ══════════════════════════════════════════════════════════════════
-- Settle cash-on-delivery on receipt (2026-11-13)
--
-- Cash (COD) orders are created with payment_status = 'unpaid' and the
-- app's Confirm Receipt flow only flips status → 'received', never
-- touching payment_status. Result: delivered-and-paid-in-cash orders
-- sat at ₱0 sales and 0 sold forever, even though the money changed
-- hands at the door.
--
-- Cash changes hands exactly when the buyer confirms receipt, so the
-- receipt transition itself settles payment — server-side, where no
-- client can fake or forget it:
--   • trigger: a cash order moving into 'received' while still 'unpaid'
--     is marked 'paid' in the same write;
--   • backfill: cash orders already sitting at 'received' + 'unpaid'
--     (money already collected) are settled once, now.
--
-- Scope is deliberately narrow: only payment_method = 'cash'. GCash /
-- card orders keep their own verification flows, and 'delivered' alone
-- does not settle (the courier may still be holding the parcel).
--
-- This migration also adds the missing buyer Confirm Receipt policy.
-- There was NO customer UPDATE policy on orders at all, so the app's
-- receipt confirmation (tracking_screen → updateOrderStatus →
-- status='received') matched zero rows under RLS: the UI said
-- "Order confirmed!" while the DB stayed 'delivered'. The policy below
-- allows exactly one transition, on the buyer's own orders:
-- delivered → received. Nothing else is widened (sellers keep their own
-- status policy), and payment settlement stays server-side in the
-- trigger above — the buyer can never mark an order paid directly.
--
-- Safety: the seller has no 'received' action (manage_orders_screen —
-- received rows only appear via the buyer's confirm), and POS rows are
-- born 'received' + 'paid', so the only rows this trigger can touch are
-- genuine buyer-confirmed cash handovers.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.settle_cod_on_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NEW.status = 'received'
    AND OLD.status IS DISTINCT FROM 'received'
    AND NEW.payment_method = 'cash'
    AND NEW.payment_status = 'unpaid'
  THEN
    NEW.payment_status := 'paid';
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.settle_cod_on_receipt() IS
  'Cash is collected at handover: a cash order the buyer confirms as '
  'received is marked paid in the same write, so sales/sold counters '
  'see it. Cash-only; other methods keep their own verification.';

DROP TRIGGER IF EXISTS trg_settle_cod_on_receipt ON public.orders;
CREATE TRIGGER trg_settle_cod_on_receipt
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.settle_cod_on_receipt();

-- Buyer Confirm Receipt: own orders, delivered → received only.
DROP POLICY IF EXISTS "Customers can confirm receipt of delivered orders"
  ON public.orders;
CREATE POLICY "Customers can confirm receipt of delivered orders"
  ON public.orders FOR UPDATE
  USING (
    auth.uid() = customer_id
    AND status = 'delivered'
  )
  WITH CHECK (
    auth.uid() = customer_id
    AND status = 'received'
  );

-- Backfill: cash already collected (received + still unpaid).
UPDATE public.orders
SET payment_status = 'paid'
WHERE status = 'received'
  AND payment_method = 'cash'
  AND payment_status = 'unpaid';
