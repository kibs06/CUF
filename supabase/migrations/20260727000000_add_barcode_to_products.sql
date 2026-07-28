-- Migration: Add `barcode` column to products table
-- Purpose: Enable product-level barcode scanning at POS checkout.
--          Barcodes (EAN-13, UPC-A, QR) are scanned to quickly find products.
-- Date: July 27, 2026

-- Add the barcode column (nullable — existing products won't have barcodes)
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS barcode TEXT;

-- Add an index for fast barcode lookups during POS scanning
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(barcode)
  WHERE barcode IS NOT NULL;

COMMENT ON COLUMN public.products.barcode IS 'Scannable barcode (EAN-13, UPC-A, QR code value). Used by POS barcode scanner for quick product lookup.';
