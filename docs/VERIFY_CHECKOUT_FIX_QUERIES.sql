-- ============================================================
-- SoleVision — Checkout Fix Verification Queries
-- Run these in the Supabase SQL Editor to verify the fix.
-- Last updated: July 3, 2026 (v6 — post-fix verification)
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- STEP 1: Confirm the fix works end-to-end
-- After placing a real test order for demo_2 (size EU40),
-- run this to verify stock actually decremented:
-- ──────────────────────────────────────────────────────────────
SELECT product_id, size, stock, updated_at
FROM inventory
WHERE product_id = '5d2dadf8-680d-4d6a-b16e-153eeaf622d4';

-- Also verify the order was created correctly:
SELECT oi.order_id, oi.product_id, oi.size, oi.quantity, oi.unit_price,
       o.status, o.total_amount, o.created_at
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.product_id = '5d2dadf8-680d-4d6a-b16e-153eeaf622d4'
ORDER BY o.created_at DESC
LIMIT 5;

-- ──────────────────────────────────────────────────────────────
-- STEP 2: Rule out non-numeric sizes
-- If either query returns rows, the normalization strategy
-- needs a fallback branch for non-numeric sizes (e.g. "S", "M").
-- Flag this to a human before changing the trigger again.
-- ──────────────────────────────────────────────────────────────
SELECT DISTINCT size FROM product_variants
WHERE size !~ '^[A-Za-z]*[0-9]+$';

SELECT DISTINCT size FROM inventory
WHERE size !~ '^[A-Za-z]*[0-9]+$';

-- ──────────────────────────────────────────────────────────────
-- STEP 3: Check for orphaned/missing inventory rows
-- If this returns rows, those products have stock in
-- product_variants but NO matching inventory row at all.
-- The trigger will still fail for these (nothing to match).
-- Only run Step 4 if this returns results.
-- ──────────────────────────────────────────────────────────────
SELECT pv.product_id, pv.size AS variant_size, pv.stock AS variant_stock
FROM product_variants pv
LEFT JOIN inventory inv
  ON inv.product_id = pv.product_id
  AND regexp_replace(inv.size, '\D', '', 'g') = regexp_replace(pv.size, '\D', '', 'g')
WHERE inv.product_id IS NULL;

-- ──────────────────────────────────────────────────────────────
-- STEP 4: Backfill inventory (ONLY if Step 3 found orphans)
-- ⚠️ Confirm with a human before running against production.
-- It overwrites inventory.stock with the sum from product_variants.
-- ──────────────────────────────────────────────────────────────
INSERT INTO public.inventory (product_id, size, stock, updated_at)
SELECT
  product_id,
  regexp_replace(size, '\D', '', 'g') AS size,
  SUM(stock) AS stock,
  now()
FROM public.product_variants
GROUP BY product_id, regexp_replace(size, '\D', '', 'g')
ON CONFLICT (product_id, size)
DO UPDATE SET stock = EXCLUDED.stock, updated_at = now();

-- After backfill, re-run Step 3 to confirm zero orphans:
-- SELECT pv.product_id, pv.size, pv.stock
-- FROM product_variants pv
-- LEFT JOIN inventory inv
--   ON inv.product_id = pv.product_id
--   AND regexp_replace(inv.size, '\D', '', 'g') = regexp_replace(pv.size, '\D', '', 'g')
-- WHERE inv.product_id IS NULL;

-- ──────────────────────────────────────────────────────────────
-- STEP 5: Check for duplicate product_variants rows
-- If this returns rows, a product has duplicate variants for the
-- same (product_id, size, color) combination. This can cause
-- double-counting in stock calculations and confusing UI.
-- ──────────────────────────────────────────────────────────────
SELECT
  product_id, size, color,
  COUNT(*) AS duplicate_count,
  MIN(id) AS keep_id,
  array_agg(id ORDER BY id) AS all_ids
FROM product_variants
GROUP BY product_id, size, color
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- ──────────────────────────────────────────────────────────────
-- STEP 6: Cleanup duplicate variants (ONLY if Step 5 found dupes)
-- ⚠️ Confirm with a human before running against production.
-- Keeps the first row (by id) for each (product_id, size, color).
-- ──────────────────────────────────────────────────────────────
-- DELETE FROM product_variants
-- WHERE id NOT IN (
--   SELECT MIN(id)
--   FROM product_variants
--   GROUP BY product_id, size, color
-- );

-- ──────────────────────────────────────────────────────────────
-- STEP 7: Verify cart clearing after order
-- After placing a test order, check that ordered items are
-- removed from cart_items. If rows remain, the cart clear fix
-- did not work.
-- ──────────────────────────────────────────────────────────────
-- Replace USER_ID with the test user's actual ID
SELECT ci.id, ci.product_id, ci.variant_id, ci.quantity, ci.created_at
FROM cart_items ci
WHERE ci.user_id = 'USER_ID'
ORDER BY ci.created_at DESC;

-- ──────────────────────────────────────────────────────────────
-- STEP 8: Verify order_items were created correctly
-- Check that all order_items have valid sizes that match
-- inventory format (bare numbers, not prefixed).
-- ──────────────────────────────────────────────────────────────
SELECT
  oi.order_id,
  oi.product_id,
  oi.size,
  oi.quantity,
  oi.unit_price,
  p.name AS product_name,
  CASE
    WHEN oi.size ~ '^[0-9]+$' THEN 'numeric'
    WHEN oi.size ~ '^[A-Za-z]*[0-9]+$' THEN 'prefixed'
    ELSE 'non-numeric'
  END AS size_format
FROM order_items oi
JOIN products p ON p.id = oi.product_id
WHERE oi.created_at > now() - interval '1 day'
ORDER BY oi.created_at DESC
LIMIT 20;

-- ──────────────────────────────────────────────────────────────
-- BONUS: Quick overview of all products' inventory vs variants
-- Useful for spotting data inconsistencies at a glance.
-- ──────────────────────────────────────────────────────────────
SELECT
  p.name,
  p.id AS product_id,
  json_agg(DISTINCT jsonb_build_object('size', inv.size, 'stock', inv.stock)) AS inventory_rows,
  json_agg(DISTINCT jsonb_build_object('size', pv.size, 'color', pv.color, 'stock', pv.stock)) AS variant_rows
FROM products p
LEFT JOIN inventory inv ON inv.product_id = p.id
LEFT JOIN product_variants pv ON pv.product_id = p.id
WHERE p.is_active = true
GROUP BY p.id, p.name
ORDER BY p.name;
