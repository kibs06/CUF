-- ══════════════════════════════════════════════════════════════════
-- Cash / COD orders: one submission, one order.
--
-- Placing a cash order is a plain client INSERT into public.orders, so a
-- submit that timed out after the row landed was indistinguishable from a
-- submit that never arrived: the customer retried and got a second order,
-- stock and all. Nothing on the row identified the attempt.
--
-- The app now sends a key it keeps for the life of one checkout screen
-- (rotated once an order exists), and this index makes a second insert with
-- that key impossible. The client reads the 23505 as "the first attempt
-- succeeded" and opens the order it already has instead of writing another.
--
-- GCash is untouched: its checkout goes through create_gcash_checkout and is
-- already capped by uq_orders_one_awaiting_payment_confirmation_per_customer,
-- which allows one open awaiting-payment order per customer. Cash orders are
-- status 'pending', so the two guards never overlap.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS idempotency_key text;

COMMENT ON COLUMN public.orders.idempotency_key IS
  'Client-generated key for one checkout submission. A retried submit reuses it, so an insert that timed out after it landed cannot become a second order. NULL on POS and GCash orders and on rows written before this column existed.';

-- 8–64 characters: a UUID today, open enough to swap identifier later without
-- another migration, and bounded so a client cannot park text on the row.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_idempotency_key_len;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_idempotency_key_len
  CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 8 AND 64);

-- Partial, like every other guard on this table: POS rows, GCash rows and the
-- whole pre-change history carry no key, and NULLs must not collide.
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_customer_idempotency_key
  ON public.orders (customer_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMENT ON INDEX public.uq_orders_customer_idempotency_key IS
  'One order per (customer, checkout key). A retried submit after a timeout hits this index and the app answers with the order the first attempt created.';
