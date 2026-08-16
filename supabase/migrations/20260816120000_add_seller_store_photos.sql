-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller application — store photos (storefront + product)
-- Date: 2026-08-16
--
-- WHY THIS CHANGE:
--   Admins reviewing a Tier 1 application can verify the applicant really
--   runs a store by looking at photos of it. Step 4 (Storefront) now asks
--   for a photo of the front of the store and a photo of a product.
--
--   The storefront photo is uploaded to the PUBLIC `store-assets` bucket
--   (path `{userId}/storefront.jpg`) because it doubles as the store's
--   banner: post-approval, StoreService.createStore falls back to
--   `profiles.store_front_url` when the seller doesn't pick a new banner.
--   The product photo goes to the PRIVATE `seller-verification-docs`
--   bucket like the ID/selfie/barangay proof (admin review only).
--
-- Additive + nullable: pre-migration applications are unaffected (legacy
-- rows simply have no store photos).
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS store_front_url     TEXT,
    ADD COLUMN IF NOT EXISTS product_photo_urls  TEXT[];

COMMENT ON COLUMN public.profiles.store_front_url IS
    'Tier 1: storage path of the applicant''s store-front photo (PUBLIC bucket store-assets — doubles as the store banner via StoreService.createStore).';
COMMENT ON COLUMN public.profiles.product_photo_urls IS
    'Tier 1: storage paths of the applicant''s 5 product photos (private bucket seller-verification-docs, admin review only).';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--     AND column_name IN ('store_front_url','product_photo_url');
