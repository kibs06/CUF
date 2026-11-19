-- 20261119190000_payout_receipt_notice.sql
--
-- Records when the "your payout was sent" receipt was delivered, so a retried
-- or double-clicked admin request cannot mail the seller twice.
--
-- `send-payout-receipt` reads this column defensively (`select *`) and simply
-- skips the stamp while it is missing, so the function works before this runs —
-- it is only the duplicate guard that waits for this migration.
--
-- NOT APPLIED to the hosted project. Apply with:
--   supabase db push

ALTER TABLE public.seller_payouts
  ADD COLUMN IF NOT EXISTS payout_notice_sent_at timestamptz;

COMMENT ON COLUMN public.seller_payouts.payout_notice_sent_at IS
  'When send-payout-receipt delivered the seller''s emailed receipt. NULL = not yet sent.';
