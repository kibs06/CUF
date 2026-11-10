-- Bell + push for review events: a seller is told on the bell they read
-- (`seller_notifications`, store-scoped) when a product gets a review.
-- The customer side (`notifications`, per-user) needs no change: its
-- `category` enum already admits 'review', which reply/like notices use.
ALTER TABLE public.seller_notifications
  DROP CONSTRAINT IF EXISTS seller_notifications_type_check;

ALTER TABLE public.seller_notifications
  ADD CONSTRAINT seller_notifications_type_check
    CHECK (
      type IN (
        'new_order',
        'stale_order',
        'low_stock',
        'custom_order_request',
        'new_message',
        'model_request',
        'return_request',
        'new_review'
      )
    );
