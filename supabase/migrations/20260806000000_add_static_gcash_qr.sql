-- ══════════════════════════════════════════════════════════════════
-- Migration: Static seller GCash QR (POS manual-confirmation flow)
-- Date: 2026-08-06
-- Purpose: Replace PayMongo-generated dynamic GCash QR at POS with a
--          seller-uploaded static "Receive Money" QR image. The customer
--          scans the seller's own QR and pays their GCash wallet directly;
--          the seller confirms receipt manually (no webhook).
--
-- History: These columns were first added by
--          20260729110000_add_gcash_manual_verification.sql, then DROPPED by
--          20260730000000_add_paymongo_gcash_columns.sql when PayMongo
--          replaced the manual flow. We re-add them (IF NOT EXISTS so the
--          migration is safe on any environment) to restore the static-QR
--          model.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS gcash_qr_url TEXT,
  ADD COLUMN IF NOT EXISTS gcash_number TEXT,
  ADD COLUMN IF NOT EXISTS gcash_account_name TEXT;

COMMENT ON COLUMN public.stores.gcash_qr_url IS
  'Public URL of the store GCash "Receive Money" QR image. Uploaded by the seller once, displayed at POS checkout for customers to scan.';
COMMENT ON COLUMN public.stores.gcash_number IS
  'GCash mobile number shown under the QR at checkout for verification.';
COMMENT ON COLUMN public.stores.gcash_account_name IS
  'Registered GCash account name shown under the QR at checkout so customers can confirm they are paying the right shop.';
