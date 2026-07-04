-- ============================================================
-- SoleVision — Hard Fix Cleanup: Duplicate variants + orphaned inventory
-- Date: July 3, 2026
-- Purpose: Clean up data integrity issues that may be contributing
--   to the false "no longer available" checkout error.
-- ============================================================

-- STEP 1: Identify duplicate product_variants rows
-- (same product_id + size + color = duplicate)
SELECT
  product_id, size, color,
  COUNT(*) AS duplicate_count,
  MIN(id) AS keep_id,
  array_agg(id ORDER BY id) AS all_ids
FROM product_variants
GROUP BY product_id, size, color
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- STEP 2: Remove duplicate product_variants (keeps first row by id)
-- ⚠️ Run Step 1 first to verify what will be deleted
DELETE FROM product_variants
WHERE id NOT IN (
  SELECT MIN(id)
  FROM product_variants
  GROUP BY product_id, size, color
);

-- STEP 3: Identify orphaned inventory rows
-- (inventory row with no matching product_variants after dedup)
SELECT pv.product_id, pv.size AS variant_size, pv.stock AS variant_stock
FROM product_variants pv
LEFT JOIN inventory inv
  ON inv.product_id = pv.product_id
  AND regexp_replace(inv.size, '\D', '', 'g') = regexp_replace(pv.size, '\D', '', 'g')
WHERE inv.product_id IS NULL;

-- STEP 4: Backfill inventory from product_variants (after dedup)
-- ⚠️ Run Step 3 first — only run this if orphans exist
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

-- STEP 5: Verify cart_items size column coverage after migration
SELECT
  COUNT(*) AS total_rows,
  COUNT(size) AS rows_with_size,
  COUNT(*) - COUNT(size) AS rows_without_size
FROM cart_items;

-- STEP 6: Identify non-numeric sizes that break trigger normalization
SELECT DISTINCT size FROM product_variants
WHERE size !~ '^[A-Za-z]*[0-9]+$';

SELECT DISTINCT size FROM inventory
WHERE size !~ '^[A-Za-z]*[0-9]+$';
