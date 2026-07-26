-- Add amount_tendered and change_amount columns to orders table.
-- These are only meaningful for POS cash transactions but the columns
-- exist on all orders for simplicity (NULL for online/GCash orders).

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS amount_tendered NUMERIC,
ADD COLUMN IF NOT EXISTS change_amount NUMERIC;

COMMENT ON COLUMN public.orders.amount_tendered IS 'Cash amount tendered by customer (POS cash payments only). NULL for online/GCash orders.';
COMMENT ON COLUMN public.orders.change_amount IS 'Change given back to customer (POS cash payments only). Computed as amount_tendered - total_amount.';
