-- ══════════════════════════════════════════════════════════════════
-- Migration: Lock down storage bucket MIME types and size limits
-- Date: 2026-09-01
--
-- WHY THIS CHANGE:
--   Both `seller-verification-docs` (private) and `store-assets` (public)
--   currently have NO allowed_mime_types and NO file_size_limit at the
--   bucket level. A malicious actor could upload an HTML/JS payload
--   renamed as .jpg, or a multi-gigabyte junk file, directly via the
--   Supabase REST API (bypassing the app entirely).
--
--   This migration sets:
--   - allowed_mime_types: only real image MIME types (no PDFs — the
--     image_picker cannot pick PDFs and the existing Image.network
--     rendering does not support PDFs)
--   - file_size_limit: 10 MB per file
--
-- IMPORTANT CAVEAT:
--   Supabase's allowed_mime_types check relies on the Content-Type
--   header the client sends, which a malicious actor can still spoof
--   directly against the API. This layer blocks casual/accidental
--   mismatches and anyone going through the normal app. It is NECESSARY
--   but NOT SUFFICIENT on its own — Layer 3 (server-side magic-byte
--   verification via Edge Function) closes the actual content-based gap.
-- ══════════════════════════════════════════════════════════════════

-- ── Private verification bucket ──────────────────────────────────
-- Stores: ID photos, selfies, barangay proofs, DTI/BIR/permit docs,
-- product photos. Owner-only + admin read via RLS (already enforced).
UPDATE storage.buckets
SET
    file_size_limit = 10485760,  -- 10 MB in bytes
    allowed_mime_types = ARRAY['image/jpeg', 'image/png']
WHERE id = 'seller-verification-docs';

-- ── Public store-assets bucket ───────────────────────────────────
-- Stores: store front photos (doubles as store banner). Public read.
-- This is the strictest bucket — no PDFs, ever, since anyone can
-- view these files in a browser context (highest XSS surface area).
UPDATE storage.buckets
SET
    file_size_limit = 10485760,  -- 10 MB in bytes
    allowed_mime_types = ARRAY['image/jpeg', 'image/png']
WHERE id = 'store-assets';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Confirm MIME types are set:
-- SELECT id, public, file_size_limit, allowed_mime_types
--   FROM storage.buckets
--   WHERE id IN ('seller-verification-docs', 'store-assets');
--
-- -- Expected result:
-- --   seller-verification-docs:  public=false, file_size_limit=10485760,
-- --                               allowed_mime_types={'image/jpeg','image/png'}
-- --   store-assets:              public=true,  file_size_limit=10485760,
-- --                               allowed_mime_types={'image/jpeg','image/png'}
