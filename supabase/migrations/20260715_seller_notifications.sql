-- Seller Notifications table
-- Stores notifications for sellers: new orders, stale orders, low stock, custom requests

CREATE TABLE IF NOT EXISTS seller_notifications (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id    UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN ('new_order', 'stale_order', 'low_stock', 'custom_order_request')),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  reference_id UUID, -- order_id / product_id / custom request id for tap-to-navigate
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient queries
CREATE INDEX IF NOT EXISTS idx_seller_notifications_store_id ON seller_notifications(store_id);
CREATE INDEX IF NOT EXISTS idx_seller_notifications_unread ON seller_notifications(store_id, is_read) WHERE is_read = FALSE;

-- RLS policies: seller can only read/update their own store's notifications
ALTER TABLE seller_notifications ENABLE ROW LEVEL SECURITY;

-- Sellers can read their own store's notifications
CREATE POLICY "Sellers can read own store notifications"
  ON seller_notifications
  FOR SELECT
  TO authenticated
  USING (
    store_id IN (
      SELECT id FROM stores WHERE owner_id = auth.uid()
    )
  );

-- Sellers can update (mark as read) their own store's notifications
CREATE POLICY "Sellers can update own store notifications"
  ON seller_notifications
  FOR UPDATE
  TO authenticated
  USING (
    store_id IN (
      SELECT id FROM stores WHERE owner_id = auth.uid()
    )
  )
  WITH CHECK (
    store_id IN (
      SELECT id FROM stores WHERE owner_id = auth.uid()
    )
  );

-- Service role can insert notifications (for triggers/functions)
CREATE POLICY "Service role can insert notifications"
  ON seller_notifications
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Allow authenticated users to insert (for app-side creation)
CREATE POLICY "Authenticated users can insert notifications"
  ON seller_notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (
    store_id IN (
      SELECT id FROM stores WHERE owner_id = auth.uid()
    )
  );

-- Enable Realtime for live badge updates
ALTER PUBLICATION supabase_realtime ADD TABLE seller_notifications;
