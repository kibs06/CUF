-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller application v2 — personal details, business docs,
-- store location + store tags
-- Date: 2026-08-17
--
-- Expands the seller application flow from 4 steps to 5:
--   Step 3 (Community)  now also collects birthday, gender and the store
--                       location (picked from the map) alongside the
--                       CUFMAI/barangay proof.
--   Step 4 (Business)   NEW — REQUIRED DTI cert, BIR COR, and
--                       mayor's/barangay permit. Reuses the existing
--                       seller_business_docs table (created by
--                       20260812000000_add_seller_tiered_verification.sql),
--                       whose owner-insert/update RLS already lets the
--                       applicant write their row; the row is created at
--                       application submit with status 'pending'.
--   Step 5 (Storefront) now also collects store tags (a store-specific
--                       preset vocabulary — handmade, family-owned,
--                       Carcar-made… — at least one required).
--
-- New profile columns are all nullable/additive so pre-migration users
-- are unaffected. birthday/gender already exist (customer-profile
-- migration 20260812130000) and are re-listed only for documentation.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS birthday          DATE,   -- exists (20260812130000)
    ADD COLUMN IF NOT EXISTS gender            TEXT,   -- exists (20260812130000)
    ADD COLUMN IF NOT EXISTS store_location    TEXT,
    ADD COLUMN IF NOT EXISTS store_lat         DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS store_lng         DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS store_tags        TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.profiles.store_location IS
    'Seller application Step 3: formatted store/business address picked from the map. Pre-fills CreateStoreScreen''s Location field.';
COMMENT ON COLUMN public.profiles.store_lat IS
    'Seller application Step 3: latitude of the picked store location.';
COMMENT ON COLUMN public.profiles.store_lng IS
    'Seller application Step 3: longitude of the picked store location.';
COMMENT ON COLUMN public.profiles.store_tags IS
    'Seller application Step 5: store tag ids (store-specific preset vocabulary — handmade, family-owned, Carcar-made…). Copied to stores.tags when the store is created.';

-- Store tags on the live store row (copied from profiles.store_tags at
-- store creation, editable afterwards via Edit Store).
ALTER TABLE public.stores
    ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.stores.tags IS
    'Store tag ids (store-specific preset vocabulary), collected during the seller application and editable via Edit Store.';
