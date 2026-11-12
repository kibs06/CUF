-- ══════════════════════════════════════════════════════════════════
-- Settle cash at handover, not at the buyer's confirmation (2026-11-12)
--
-- `20261113000000_settle_cod_on_receipt.sql` settled a cash order when it
-- reached 'received' — the buyer tapping Confirm receipt. That put the
-- seller's own numbers in the customer's hands: a seller who had handed
-- the parcel to the courier (status 'delivered') still saw ₱0 in today's
-- sales, 0 units in every sold counter and an empty top-products list
-- until the buyer opened the app. Orders nobody ever confirmed stayed
-- 'unpaid' and never counted at all.
--
-- Handover is the seller's moment, so the sale starts there:
--   • trigger: a cash order entering 'delivered' OR 'received' while still
--     'unpaid' is marked paid in the same write. 'received' stays in the
--     list as the fallback path (a pickup order can go straight from
--     'delivered' to the counter), so no handover is missed either way;
--   • backfill: cash orders already sitting at 'delivered' + 'unpaid' are
--     settled once, now.
--
-- Scope stays narrow. Only payment_method = 'cash' — GCash and card keep
-- their own verification flows and are already 'paid' before handover, so
-- an unverified delivery is never counted as money. Every sales query
-- (lib/services/sales_service.dart, product_sales()) filters
-- `status <> 'cancelled' AND payment_status = 'paid'`, so a cancelled
-- order drops back out on its own.
--
-- The trigger keeps the `BEFORE UPDATE OF status` shape: it can only fire
-- when a status transition is what touches the row.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.settle_cod_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NEW.status IN ('delivered', 'received')
    AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.payment_method = 'cash'
    AND NEW.payment_status = 'unpaid'
  THEN
    NEW.payment_status := 'paid';
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.settle_cod_on_delivery() IS
  'Cash is collected at handover: a cash order the seller marks delivered '
  '(or a buyer confirms received) is marked paid in the same write, so the '
  'seller''s sales and sold counters see it without waiting on the buyer. '
  'Cash-only; other methods keep their own verification.';

DROP TRIGGER IF EXISTS trg_settle_cod_on_receipt ON public.orders;
DROP TRIGGER IF EXISTS trg_settle_cod_on_delivery ON public.orders;
CREATE TRIGGER trg_settle_cod_on_delivery
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.settle_cod_on_delivery();

-- The receipt-time function has no callers left (the trigger above
-- replaced its only use), and leaving it behind invites the old rule back.
DROP FUNCTION IF EXISTS public.settle_cod_on_receipt();

-- Backfill: cash handed over, still unpaid on paper.
UPDATE public.orders
SET payment_status = 'paid'
WHERE status IN ('delivered', 'received')
  AND payment_method = 'cash'
  AND payment_status = 'unpaid';
