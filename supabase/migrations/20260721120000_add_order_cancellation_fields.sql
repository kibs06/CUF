-- Add cancellation-related fields to the orders table
-- Supports the customer-initiated cancellation flow

-- Cancellation reason (predefined list or 'Other' with details)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

-- Free-text details (required when reason is 'Other')
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_details TEXT;

-- Timestamp when cancellation was requested/completed
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Index for efficient filtering by cancellation status
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_reason ON orders(cancellation_reason) WHERE cancellation_reason IS NOT NULL;

-- Add 'cancellation_requested' to the status check constraint if it exists
-- This allows the new status for processing orders awaiting seller approval
DO $$
BEGIN
  -- Check if there's a check constraint on status
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname LIKE '%orders%status%'
    AND contype = 'c'
  ) THEN
    -- Drop and recreate with new status
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
    ALTER TABLE orders ADD CONSTRAINT orders_status_check
      CHECK (status IN (
        'pending', 'placed', 'preparing', 'ready', 'delivered',
        'received', 'cancelled', 'cancellation_requested'
      ));
  END IF;
END $$;

COMMENT ON COLUMN orders.cancellation_reason IS 'Reason for order cancellation (from predefined list)';
COMMENT ON COLUMN orders.cancellation_details IS 'Additional details when reason is Other';
COMMENT ON COLUMN orders.cancelled_at IS 'Timestamp when order was cancelled or cancellation was requested';
