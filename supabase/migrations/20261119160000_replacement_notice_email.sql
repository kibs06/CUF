-- ══════════════════════════════════════════════════════════════════
-- Replacement notice email stamp
-- Date: 2026-11-19
--
-- `send-replacement-notice` mails the customer when the store approves a
-- product replacement. This column is the idempotency guard: set once the
-- Gmail SMTP send succeeded, so a retried invoke cannot mail the customer a
-- second time. NULL means "not sent yet".
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS replacement_notice_emailed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.replacement_notice_emailed_at IS
  'When the "your replacement is approved" email went out. NULL = not sent; set by send-replacement-notice after a successful SMTP send.';
