-- ══════════════════════════════════════════════════════════════════
-- CLEANUP: Orphaned orders with 0 order_items
-- Date: July 4, 2026
-- Context: The createOrder() function inserts the orders row first,
--   then inserts order_items in separate (non-atomic) calls. When the
--   order_items insert fails (e.g., DB trigger P0001), the orders row
--   is left orphaned with 0 items. This script finds and deletes them.
-- ══════════════════════════════════════════════════════════════════

-- STEP 1: Preview — see which orders will be deleted
SELECT
    o.id AS order_id,
    o.customer_id,
    o.store_id,
    o.status,
    o.total_amount,
    o.created_at,
    (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM order_items oi WHERE oi.order_id = o.id
)
ORDER BY o.created_at DESC;

-- STEP 2: Delete orphaned orders (uncomment when ready)
-- DELETE FROM orders
-- WHERE NOT EXISTS (
--     SELECT 1 FROM order_items oi WHERE oi.order_id = orders.id
-- );

-- STEP 3: Verify — should return 0 rows after cleanup
-- SELECT o.id, o.created_at
-- FROM orders o
-- WHERE NOT EXISTS (
--     SELECT 1 FROM order_items oi WHERE oi.order_id = o.id
-- );
