-- ══════════════════════════════════════════════════════════════════
-- 20261119235000_bulk_deposit_receipt.sql
--
-- The bulk-reservation deposit is real money, and until now the customer's only
-- proof of it was a push notification. The shop could say "deposit confirmed"
-- and there was nothing in the customer's inbox to keep, forward to their own
-- books, or show if a balance was ever disputed.
--
-- This adds the paper trail the order receipt already has on `orders`:
--
--   deposit_receipt_emailed_at  when the deposit receipt email went out.
--                               The send-bulk-deposit-receipt function writes
--                               it only after SMTP accepts the message, so a
--                               retried call is a no-op rather than a second
--                               copy in the customer's inbox.
--   deposit_receipt_email_to    the address it actually went to. Kept because
--                               the customer can change their account email
--                               later, and support needs to know where the
--                               receipt of THIS deposit was sent.
--
-- No trigger, no pg_net and no Vault entry: unlike an online order (which is
-- marked paid by a webhook that has no phone attached), a deposit is confirmed
-- by the store owner tapping Confirm in the app — the same moment the
-- deposit-confirmed push is sent. `ReservationService.confirmDeposit` invokes
-- the function with that seller's session right after the RPC returns, and the
-- function checks that the caller owns the store.
--
-- Additive and idempotent. Nothing breaks while it is unapplied: the app still
-- confirms deposits, and the function sends the receipt anyway — it just
-- cannot tell that it already did, which is stated in its log.
-- ══════════════════════════════════════════════════════════════════

begin;

alter table public.bulk_reservations
  add column if not exists deposit_receipt_emailed_at timestamptz,
  add column if not exists deposit_receipt_email_to   text;

comment on column public.bulk_reservations.deposit_receipt_emailed_at is
  'When the customer''s deposit receipt email was sent for this reservation. NULL = never sent. Written by the send-bulk-deposit-receipt edge function only after SMTP accepts the message, which is what makes a retried call a no-op.';

comment on column public.bulk_reservations.deposit_receipt_email_to is
  'The address the deposit receipt was actually sent to (the customer''s account email at confirmation time). Kept because the account email can change later.';

commit;
