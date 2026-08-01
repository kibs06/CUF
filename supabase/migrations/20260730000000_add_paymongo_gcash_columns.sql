-- Migration: Add PayMongo GCash integration columns
-- Date: July 30, 2026
-- Purpose: Support real GCash payments via PayMongo with automatic confirmation

-- Add PayMongo-specific columns to orders
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gcash_transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS payment_verified_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.gcash_transaction_id IS
  'PayMongo payment ID returned by webhook when payment is confirmed';
COMMENT ON COLUMN public.orders.payment_verified_at IS
  'Timestamp when PayMongo webhook confirmed the payment';

-- Update payment_status CHECK constraint to allow 'pending' state
-- GCash orders will sit in 'pending' between QR generation and webhook confirmation
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_payment_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_payment_status_check
    CHECK (payment_status IN ('paid', 'unpaid', 'pending'));

-- Drop manual GCash flow columns from stores (replaced by PayMongo)
ALTER TABLE public.stores
  DROP COLUMN IF EXISTS gcash_qr_url,
  DROP COLUMN IF EXISTS gcash_number,
  DROP COLUMN IF EXISTS gcash_account_name;

-- Drop the manual verification column from orders (repurposed for PayMongo source ID)
-- Actually, KEEP gcash_reference_number - we'll repurpose it to store PayMongo's source ID
-- This avoids breaking existing receipt-display code that references this column
