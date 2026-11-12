-- ══════════════════════════════════════════════════════════════════
-- Stamp the handover moment so sales are dated by delivery (2026-11-12)
--
-- Every seller sales figure buckets by `orders.created_at` — the day the
-- order was placed. An order placed Friday and handed to the courier
-- Monday shows up in Friday's sales, so "today's sales" can be decided
-- by orders placed days ago. The sale belongs to the handover, so the
-- handover needs its own timestamp:
--   • `orders.delivered_at`: stamped the first time an order enters
--     'delivered' (or 'received' as the pickup fallback), and on INSERT
--     for rows born handed-over (POS rows are created 'received').
--   • Backfill: the real moment from order_status_history where it
--     exists, else created_at for rows already past handover.
--
-- Rules the stamp follows:
--   • First handover wins — a declined return moving the order back to
--     'received'/'delivered' does not move the sale's date.
--   • Rows that never reached handover ('placed'/'preparing'/'ready',
--     even prepaid ones) stay NULL: the sale has not happened yet and
--     must not sit in any day's figure.
--   • Reversed rows are not un-stamped: the sales queries keep excluding
--     'cancelled' themselves, and 'replaced' still reads as revenue.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.stamp_delivered_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- A row born handed-over (POS sales are created 'received').
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('delivered', 'received')
      AND NEW.delivered_at IS NULL
    THEN
      NEW.delivered_at := COALESCE(NEW.created_at, now());
    END IF;
    RETURN NEW;
  END IF;

  -- First handover wins: never move the sale's date on a re-delivery.
  IF NEW.status IN ('delivered', 'received')
    AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.delivered_at IS NULL
  THEN
    NEW.delivered_at := now();
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.stamp_delivered_at() IS
  'Stamps orders.delivered_at at the first handover (delivered, or '
  'received as the pickup fallback) so sales are dated by delivery, '
  'not by order placement.';

COMMENT ON COLUMN public.orders.delivered_at IS
  'First handover timestamp (delivered, or received for pickups). '
  'NULL until the handover happens. Seller sales bucket by this, not created_at.';

DROP TRIGGER IF EXISTS trg_stamp_delivered_at_ins ON public.orders;
CREATE TRIGGER trg_stamp_delivered_at_ins
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.stamp_delivered_at();

DROP TRIGGER IF EXISTS trg_stamp_delivered_at_upd ON public.orders;
CREATE TRIGGER trg_stamp_delivered_at_upd
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.stamp_delivered_at();

-- Backfill: the real handover moment from the status history where the
-- order passed through a handover status, else created_at for rows
-- already sitting past handover. Rows that never handed over stay NULL.
UPDATE public.orders o
SET delivered_at = h.first_handover
FROM (
  SELECT order_id, min(changed_at) AS first_handover
  FROM public.order_status_history
  WHERE status IN ('delivered', 'received')
  GROUP BY order_id
) h
WHERE o.id = h.order_id
  AND o.delivered_at IS NULL;

UPDATE public.orders
SET delivered_at = created_at
WHERE delivered_at IS NULL
  AND status IN ('delivered', 'received', 'replaced',
                 'replacement_received', 'return_requested', 'refunded');

CREATE INDEX IF NOT EXISTS idx_orders_delivered_at
  ON public.orders (delivered_at);
