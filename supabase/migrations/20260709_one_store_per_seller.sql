-- ══════════════════════════════════════════════════════════════════
-- Migration: Enforce one store per seller
-- Date: July 9, 2026
-- Purpose: Add a UNIQUE constraint on stores.owner_id so the database
--          itself prevents a seller from creating multiple stores,
--          even if the app-level guard is bypassed.
--
-- Steps:
--   1. Check for existing duplicates (must resolve before applying)
--   2. Add the UNIQUE constraint
-- ══════════════════════════════════════════════════════════════════

-- Step 1: Check for sellers who already have multiple stores.
-- Run this FIRST. If it returns rows, resolve the data before applying the constraint.
-- SELECT owner_id, count(*) FROM stores GROUP BY owner_id HAVING count(*) > 1;

-- Step 2: Add UNIQUE constraint on owner_id.
-- This will FAIL if any seller already has 2+ stores — resolve those first.
ALTER TABLE public.stores
    ADD CONSTRAINT unique_owner_store
    UNIQUE (owner_id);

-- Verify the constraint exists:
-- SELECT conname, contype FROM pg_constraint WHERE conrelid = 'stores'::regclass AND contype = 'u';
