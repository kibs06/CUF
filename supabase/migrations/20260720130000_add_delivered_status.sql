-- Part D: Add 'delivered' status for customer Confirm Receipt flow.
-- The order lifecycle becomes:
--   pending → preparing → ready → delivered → received
-- where 'delivered' = seller handed off to courier / at pickup location,
-- and 'received' = customer confirms receipt (or auto-confirm).

-- 1. Drop the old constraint
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

-- 2. Add 'delivered' to the allowed statuses
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'delivered', 'received', 'cancelled'));
