-- ============================================================
-- SoleVision: Backfill inventory table from product_variants
-- Run this ONCE in the Supabase SQL Editor after deploying
-- the code fix that adds _syncInventoryFromVariants().
-- ============================================================

-- Step 1 — Add unique constraint (required for upsert support)
-- Skip if it already exists (will error with "already exists", which is fine)
ALTER TABLE public.inventory
  ADD CONSTRAINT inventory_product_size_unique UNIQUE (product_id, size);

-- Step 2 — Backfill inventory from product_variants
-- Aggregates stock by size (sums across all colors for the same size)
-- Uses ON CONFLICT to update rows that already exist
INSERT INTO public.inventory (product_id, size, stock, updated_at)
SELECT
  product_id,
  size,
  SUM(stock) AS stock,
  now() AS updated_at
FROM public.product_variants
WHERE size IS NOT NULL AND size <> ''
GROUP BY product_id, size
ON CONFLICT (product_id, size) DO UPDATE
  SET stock = EXCLUDED.stock,
      updated_at = now();
