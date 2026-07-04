-- ══════════════════════════════════════════════════════════════════
-- Migration: Add DELETE policy on orders table
-- Date: July 4, 2026
-- Context: createOrder() inserts the orders row first, then order_items
--   in separate calls. If order_items fails, the orders row is orphaned.
--   The app's _cleanupOrphanedOrder() tries to delete it, but RLS blocks
--   the delete because no DELETE policy exists. This migration adds one,
--   scoped to pending orders only (customers cannot delete fulfilled orders).
-- ══════════════════════════════════════════════════════════════════

-- Users can delete their own orders, but only while status is 'pending'
-- (i.e., before the seller has started processing).
CREATE POLICY "Users can delete their own pending orders"
    ON public.orders FOR DELETE USING (
        auth.uid() = customer_id AND status = 'pending'
    );
