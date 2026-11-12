-- ══════════════════════════════════════════════════════════════════
-- How the replacement is delivered: in-store swap vs shipped
-- Date: 2026-11-12
--
-- `replaced` is stamped the moment the seller approves the return, but
-- the policy has two delivery paths and they mean different things to
-- the customer:
--
--   • in_store — inspect at the counter, hand the replacement over on the
--                spot. The order is genuinely finished.
--   • shipped  — the customer mailed the pair back, so the replacement
--                still has to travel. `replaced` is approved, not done.
--
-- Without this the customer reads "Replaced" and wonders where the shoes
-- are, and support cannot tell an approved-but-not-sent replacement from
-- a completed swap. The tracking columns exist only for the shipped
-- path; they are NULL for an in-store swap.
--
-- Deliberately NOT a new order status: `replaced` stays the terminal
-- state, so every existing filter, chip and RPC that already accepts it
-- keeps working. The path rides alongside as data.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS replacement_method TEXT,
  ADD COLUMN IF NOT EXISTS replacement_carrier TEXT,
  ADD COLUMN IF NOT EXISTS replacement_tracking_number TEXT,
  ADD COLUMN IF NOT EXISTS replacement_shipped_at TIMESTAMPTZ;

-- Constrained to the two policy paths so a typo cannot create a third.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_replacement_method_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_replacement_method_check
    CHECK (
      replacement_method IS NULL
      OR replacement_method IN ('in_store', 'shipped')
    );

COMMENT ON COLUMN public.orders.replacement_method IS
  'How the approved replacement is delivered: in_store (on-the-spot swap after inspection) or shipped (customer mailed the pair back; replacement travels after inspection). NULL for orders approved before the path was recorded.';

COMMENT ON COLUMN public.orders.replacement_carrier IS
  'Courier for a shipped replacement (NULL for in-store swaps).';

COMMENT ON COLUMN public.orders.replacement_tracking_number IS
  'Tracking number for a shipped replacement (NULL for in-store swaps, or until the seller dispatches).';

COMMENT ON COLUMN public.orders.replacement_shipped_at IS
  'When the seller dispatched the shipped replacement. NULL = not dispatched yet, or an in-store swap.';

-- Sellers edit these after approval (adding the tracking number when the
-- courier picks the parcel up), so the store-scoped UPDATE policy on
-- `orders` has to be the only gate — nothing else validates them.
-- Verification: the two paths must round-trip through the existing
-- update policy without a new one:
--
--   UPDATE public.orders
--      SET replacement_method = 'shipped',
--          replacement_carrier = 'J&T',
--          replacement_tracking_number = 'TEST123',
--          replacement_shipped_at = now()
--    WHERE id = '<own store replaced order>';
--
--   UPDATE public.orders SET replacement_method = 'carrier_pigeon'
--    WHERE id = '<own store order>';   -- must fail: 23514
