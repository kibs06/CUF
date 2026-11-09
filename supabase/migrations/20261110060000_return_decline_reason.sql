-- ══════════════════════════════════════════════════════════════════
-- Return decline reason (seller must justify a refused refund)
-- Date: 2026-11-10
--
-- When a seller declines a return the order goes back to `received`.
-- The reason is stored here so the customer can see WHY in tracking
-- (and it rides along in the chat message + push sent at decline time).
-- Sellers already have a store-scoped UPDATE policy on orders, so no
-- policy change is needed for this column.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_decline_reason TEXT;

COMMENT ON COLUMN public.orders.return_decline_reason IS
  'Seller reason for declining a return_requested order (mandatory at decline time, cleared on re-request/approve)';
