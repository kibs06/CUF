-- Fix: orders_status_check CHECK constraint missing 'preparing' and 'received'
-- Root cause: The live DB constraint was created before the seller status-mapping
-- (confirmed→preparing, delivered→received) was implemented. It only allowed the
-- original UI-style values, rejecting the DB-level values the app actually sends.
--
-- Error observed: code=23514 "new row for relation 'orders' violates check constraint
-- 'orders_status_check'" when calling updateOrderStatus('confirmed') which maps to 'preparing'.
--
-- This migration drops the old constraint and replaces it with the full set of values
-- that the app and DB triggers depend on.

-- 1. Fix stale UI-style statuses that were written before the app-layer mapping.
--    The app maps: confirmed→preparing, delivered→received, but some older rows
--    may have the raw UI labels stored directly in the DB.
UPDATE public.orders SET status = 'preparing' WHERE status = 'confirmed';
UPDATE public.orders SET status = 'received'  WHERE status = 'delivered';

-- 2. Safety check: fail if any remaining rows have unexpected status values
DO $$
DECLARE
  invalid_count INTEGER;
BEGIN
  SELECT count(*) INTO invalid_count
  FROM public.orders
  WHERE status NOT IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled');

  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Found % orders with unexpected status values that could not be auto-migrated. Manual fix required.', invalid_count;
  END IF;
END $$;

-- 3. Drop the old (too-restrictive) constraint
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

-- 4. Add the corrected constraint with all statuses the app uses:
--    pending   — initial state when customer places order
--    placed    — legacy alias for pending (kept for backward compat)
--    preparing — seller confirmed (DB value for UI "confirmed")
--    ready     — seller marked ready for pickup
--    received  — seller marked delivered (DB value for UI "delivered")
--    cancelled — order cancelled by seller or customer
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled'));
