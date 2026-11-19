-- 20261119200000_seller_payout_notice.sql
--
-- Lets the seller's Notification Center hold a "Payout sent" entry
-- (`send-payout-receipt` writes it when an admin records a transfer), so the
-- notice is still there after the push is swiped away — the same place order
-- and replacement notices live.
--
-- This re-states the full list because the constraint was last widened by
-- 20261119150000; adding a type to a CHECK means restating every value it
-- admits, not just the new one.
--
-- NOT APPLIED to the hosted project. Until it runs, `send-payout-receipt`
-- logs the refused insert and reports it in its response (the payout still
-- records, the email and push still go out). Apply with:
--   supabase db push

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
        'new_review',
        'review_comment',
        'replacement_received',
        'replacement_fee',
        'verified_seller',
        'permit_expiring',
        'payout'
      )
    );
