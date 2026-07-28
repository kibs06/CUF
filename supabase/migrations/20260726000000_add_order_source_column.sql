-- Migration: Add `source` column to orders table
-- Purpose: Distinguish POS (in-person) orders from online orders.
--          POS orders are created at checkout with status='received' (completed),
--          while online orders start at 'pending' and progress through the pipeline.
-- Date: July 26, 2026

-- Add the source column with a default of 'online' for backward compatibility
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'online'
  CHECK (source IN ('online', 'pos'));

-- Add an index for efficient filtering by source (used in dashboard/reports)
CREATE INDEX IF NOT EXISTS idx_orders_source ON public.orders(source);

-- Backfill existing POS orders: any order where delivery_address = 'In-store POS'
-- was almost certainly created via the POS screen before this migration.
UPDATE public.orders
SET source = 'pos'
WHERE notes = 'In-store POS'
  AND source = 'online';

-- Update the CHECK constraint on status to also allow 'received' for POS orders
-- (it's already allowed, but we document it here for clarity)
-- The existing constraint is:
--   CHECK (status IN ('placed', 'preparing', 'ready', 'received', 'cancelled', 'pending'))
-- 'received' is already valid, so no change needed to the status constraint.

COMMENT ON COLUMN public.orders.source IS 'Order origin: online (customer checkout) or pos (in-person sale). POS orders are created with status=received (terminal).';
