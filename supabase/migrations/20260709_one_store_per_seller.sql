-- ══════════════════════════════════════════════════════════════════
-- Migration: Enforce one store per seller
-- Date: July 9, 2026
-- Purpose: Add a UNIQUE constraint on stores.owner_id so the database
--          itself prevents a seller from creating multiple stores,
--          even if the app-level guard is bypassed.
--
-- Steps:
--   1. Auto-deduplicate: keep only the most recent store per owner
--   2. Add the UNIQUE constraint
-- ══════════════════════════════════════════════════════════════════

-- Step 1: Auto-deduplicate — keep only the most recent store per owner.
-- First reassigns orders from duplicate stores to the keeper store,
-- then deletes the duplicate stores.
-- Uses id as tiebreaker when created_at is identical.
DO $$
DECLARE
  r RECORD;
  affected INT := 0;
  deleted_count INT := 0;
BEGIN
  -- For each owner with multiple stores, reassign all child rows
  -- to the keeper store, then delete the duplicates.
  FOR r IN
    SELECT DISTINCT s.owner_id
    FROM public.stores s
    INNER JOIN (
      SELECT owner_id
      FROM public.stores
      GROUP BY owner_id
      HAVING count(*) > 1
    ) dup ON s.owner_id = dup.owner_id
  LOOP
    -- Reassign orders (no CASCADE FK)
    WITH keeper AS (
      SELECT id AS keep_id FROM public.stores
      WHERE owner_id = r.owner_id
      ORDER BY created_at DESC, id ASC LIMIT 1
    )
    UPDATE public.orders
    SET store_id = keeper.keep_id
    FROM keeper
    WHERE orders.store_id IN (
      SELECT s.id FROM public.stores s
      WHERE s.owner_id = r.owner_id AND s.id != keeper.keep_id
    );
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected > 0 THEN
      RAISE NOTICE 'Reassigned % order(s) for owner %', affected, r.owner_id;
    END IF;

    -- Reassign products (no CASCADE FK)
    WITH keeper AS (
      SELECT id AS keep_id FROM public.stores
      WHERE owner_id = r.owner_id
      ORDER BY created_at DESC, id ASC LIMIT 1
    )
    UPDATE public.products
    SET store_id = keeper.keep_id
    FROM keeper
    WHERE products.store_id IN (
      SELECT s.id FROM public.stores s
      WHERE s.owner_id = r.owner_id AND s.id != keeper.keep_id
    );
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected > 0 THEN
      RAISE NOTICE 'Reassigned % product(s) for owner %', affected, r.owner_id;
    END IF;

    -- Reassign customization_requests (no CASCADE FK)
    WITH keeper AS (
      SELECT id AS keep_id FROM public.stores
      WHERE owner_id = r.owner_id
      ORDER BY created_at DESC, id ASC LIMIT 1
    )
    UPDATE public.customization_requests
    SET store_id = keeper.keep_id
    FROM keeper
    WHERE customization_requests.store_id IN (
      SELECT s.id FROM public.stores s
      WHERE s.owner_id = r.owner_id AND s.id != keeper.keep_id
    );
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected > 0 THEN
      RAISE NOTICE 'Reassigned % customization_request(s) for owner %', affected, r.owner_id;
    END IF;
  END LOOP;

  -- Now delete the duplicate stores (CASCADE handles remaining children)
  DELETE FROM public.stores
  WHERE id IN (
    SELECT s.id
    FROM public.stores s
    INNER JOIN (
      SELECT owner_id, MAX(created_at) AS latest_created
      FROM public.stores
      GROUP BY owner_id
      HAVING count(*) > 1
    ) dup ON s.owner_id = dup.owner_id
    LEFT JOIN LATERAL (
      SELECT id AS keep_id
      FROM public.stores
      WHERE owner_id = s.owner_id
      ORDER BY created_at DESC, id ASC
      LIMIT 1
    ) keeper ON true
    WHERE s.id != keeper.keep_id
  );
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  IF deleted_count > 0 THEN
    RAISE NOTICE 'Deleted % duplicate store(s) to enforce one-store-per-seller', deleted_count;
  END IF;
END $$;

-- Step 2: Add UNIQUE constraint on owner_id.
-- Safe now because duplicates were removed above.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'unique_owner_store' AND conrelid = 'stores'::regclass
  ) THEN
    ALTER TABLE public.stores
        ADD CONSTRAINT unique_owner_store
        UNIQUE (owner_id);
  END IF;
END $$;

-- Verify the constraint exists:
-- SELECT conname, contype FROM pg_constraint WHERE conrelid = 'stores'::regclass AND contype = 'u';
