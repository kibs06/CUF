-- ══════════════════════════════════════════════════════════════════
-- Allow customers to permanently delete their own cancelled orders
-- Date: 2026-08-05
--
-- Powers the My Orders → Returns tab swipe-to-delete (Undo window).
-- Deletion is strictly limited to the authenticated customer's own
-- orders that are already in the terminal 'cancelled' state.
--
-- Child rows (order_items, order_status_history) are removed via
-- ON DELETE CASCADE on orders.id.
-- ══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Customers can delete their cancelled orders" ON public.orders;
CREATE POLICY "Customers can delete their cancelled orders"
  ON public.orders FOR DELETE
  USING (
    auth.uid() = customer_id
    AND status = 'cancelled'
  );
