-- Migration: Add manual GCash payment verification fields
-- Date: July 29, 2026
-- Purpose: Support manual GCash verification — seller enters customer's reference number.
-- QR code is the seller's real GCash "Receive Money" QR uploaded and validated at upload time.

-- ── orders table ──────────────────────────────────────────────────
-- Store the GCash reference number the seller types in after customer pays
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gcash_reference_number TEXT;

COMMENT ON COLUMN public.orders.gcash_reference_number IS
  'GCash transaction reference number entered manually by seller after verifying payment';

-- ── stores table ──────────────────────────────────────────────────
-- GCash payment details displayed in POS checkout sheet
-- gcash_qr_url: uploaded GCash "Receive Money" QR image (validated by decoding before upload)
-- gcash_number / gcash_account_name: fallback text fields for manual entry
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS gcash_qr_url TEXT,
  ADD COLUMN IF NOT EXISTS gcash_number TEXT,
  ADD COLUMN IF NOT EXISTS gcash_account_name TEXT;

COMMENT ON COLUMN public.stores.gcash_qr_url IS 'URL of the store GCash QR code image (uploaded to storage, validated by QR decoding)';
COMMENT ON COLUMN public.stores.gcash_number IS 'Store GCash mobile number for manual transfer';
COMMENT ON COLUMN public.stores.gcash_account_name IS 'Registered GCash account name for verification';
