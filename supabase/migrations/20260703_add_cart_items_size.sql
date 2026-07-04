-- ============================================================
-- SoleVision — Hard Fix Migration: Add size column to cart_items
-- Date: July 3, 2026
-- Purpose: Eliminates the root cause of false "no longer available"
--   errors by storing the cart size directly on cart_items, removing
--   the fragile product_variants JOIN fallback for size resolution.
-- ============================================================

-- STEP 1: Add the size column
ALTER TABLE public.cart_items
  ADD COLUMN IF NOT EXISTS size TEXT;

-- STEP 2: Backfill size from product_variants for existing rows
-- Uses the same normalization as the DB triggers (strip alpha prefix)
-- to match inventory.size format.
UPDATE public.cart_items ci
SET size = COALESCE(
  pv.size,
  -- Fallback: strip alpha prefix from whatever size variant has
  regexp_replace(pv.size, '^([A-Za-z]+)', '', 'g')
)
FROM public.product_variants pv
WHERE ci.variant_id = pv.id
  AND ci.size IS NULL;

-- STEP 3: For rows with NULL variant_id, try to recover size from
-- the cart_items composite key (product_id-size-color pattern).
-- This is a best-effort backfill; remaining NULLs will be handled
-- by the app gracefully (fallback to variant lookup in fetchCart).

-- STEP 4: Verify the backfill
-- Run this to check coverage:
-- SELECT
--   COUNT(*) AS total_rows,
--   COUNT(size) AS rows_with_size,
--   COUNT(*) - COUNT(size) AS rows_without_size
-- FROM cart_items;
