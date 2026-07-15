-- ══════════════════════════════════════════════════════════════════
-- FIX: Add SECURITY DEFINER to inventory trigger functions
-- Date: July 4, 2026
--
-- ROOT CAUSE:
--   The `decrement_inventory_on_order` and `decrement_inventory_on_sale`
--   trigger functions run WITHOUT SECURITY DEFINER, meaning they execute
--   as the calling user (the authenticated customer). The `inventory`
--   table has RLS policies that only allow sellers and admins to UPDATE
--   rows. When a customer places an order, the trigger's UPDATE on
--   inventory is silently blocked by RLS, matching 0 rows, which causes
--   the function to raise 'Insufficient stock' — even when stock is 46.
--
--   The app's SELECT on inventory succeeds (there's a "viewable by
--   everyone" policy), so the app correctly sees stock=46. But the
--   trigger's UPDATE fails because the customer has no UPDATE policy.
--
-- FIX: Add SECURITY DEFINER so the functions run as the function owner
-- (supabase_admin), bypassing RLS. This is safe because these functions
-- only perform controlled stock decrements guarded by `stock >= quantity`.
-- ══════════════════════════════════════════════════════════════════

-- 1) Fix the ORDER trigger function
CREATE OR REPLACE FUNCTION public.decrement_inventory_on_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  update public.inventory
  set stock = stock - new.quantity
  where product_id = new.product_id
    and regexp_replace(size, '\D', '', 'g') = regexp_replace(new.size, '\D', '', 'g')
    and stock >= new.quantity;

  if not found then
    raise exception 'Insufficient stock for product % size %',
      new.product_id, new.size;
  end if;

  return new;
end;
$function$;

-- 2) Fix the SALE trigger function (POS sales have the same issue)
CREATE OR REPLACE FUNCTION public.decrement_inventory_on_sale()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  update public.inventory
  set stock = stock - new.quantity
  where product_id = new.product_id
    and regexp_replace(size, '\D', '', 'g') = regexp_replace(new.size, '\D', '', 'g')
    and stock >= new.quantity;

  if not found then
    raise exception 'Insufficient stock for product % size %',
      new.product_id, new.size;
  end if;

  return new;
end;
$function$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying the migration)
-- ══════════════════════════════════════════════════════════════════

-- A) Confirm SECURITY DEFINER is set on both functions
SELECT proname, proconfig
FROM pg_proc
WHERE proname IN ('decrement_inventory_on_order', 'decrement_inventory_on_sale');

-- B) Confirm inventory has the correct row for the test product
SELECT product_id, size, stock
FROM public.inventory
WHERE product_id = 'aaaaaaaa-0001-0001-0001-000000000001'
ORDER BY size;

-- C) Find and clean up orphaned orders (orders with 0 items)
SELECT o.id, o.status, o.total_amount, o.created_at,
       (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id)
ORDER BY o.created_at DESC;

-- D) Delete orphaned orders (uncomment after reviewing Step C results)
-- DELETE FROM orders
-- WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = orders.id);
