-- Fix: order_items unreadable for logins that can read orders without a
-- seller/admin role (e.g. a store owner whose profiles.role is not
-- seller/admin, or any live-DB drift on the schema-era policy name).
--
-- WHY: the only SELECT policy on order_items passes the order's customer or
-- a seller/admin role. The orders table itself has a THIRD path — "Sellers
-- can view orders for their store" (store owner) — with no counterpart here.
-- Result: the admin portal's Orders ITEMS column and Analytics Top Products
-- (both aggregate order_items) render 0 / "No product data yet" while every
-- other card works, because those only read orders/profiles.
--
-- WHAT: two ADDITIVE policies that mirror the orders table's own structure.
-- Nothing is dropped or narrowed; existing behavior is preserved.
--   1. Store owners can read items of their stores' orders.
--   2. Explicit admin catch-all using the same inline check as
--      "Admins can read all orders" (harmless: profiles SELECT is
--      world-readable since the recursion fix, so no 42P17 risk).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    WHERE c.relname = 'order_items'
      AND p.polname = 'Store owners can view their order items'
  ) THEN
    CREATE POLICY "Store owners can view their order items"
      ON public.order_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.stores s ON s.id = o.store_id
          WHERE o.id = order_items.order_id
            AND s.owner_id = auth.uid()
        )
      );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    WHERE c.relname = 'order_items'
      AND p.polname = 'Admins can read all order items'
  ) THEN
    CREATE POLICY "Admins can read all order items"
      ON public.order_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END
$$;
