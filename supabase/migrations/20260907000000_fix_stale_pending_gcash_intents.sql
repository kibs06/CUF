-- ══════════════════════════════════════════════════════════════════
-- 20260907000000_fix_stale_pending_gcash_intents.sql
-- Incident 2026-09-07: "Checkout cancelled" on every GCash order
-- ══════════════════════════════════════════════════════════════════
--
-- Root cause (data-verified):
--   1. A test-mode checkout (2026-08-19, order 53194fe1-…, intent amount
--      ₱410.25) was never finalized — PayMongo's webhook never delivered
--      payment.paid (payment_webhook_events has zero rows for the order),
--      so its payment_intents row stayed status='pending' forever.
--   2. pg_cron is NOT installed on this database (relation "cron.job"
--      does not exist), so the expire-online-gcash-payments sweep from
--      20260809000000 was silently never scheduled — the stale intent sat
--      19 days past expires_at, still 'pending'.
--   3. Every new checkout by that customer hit the
--      uq_payment_intents_one_pending_per_customer partial unique index
--      (it checks only status='pending', not expires_at) → the fresh order
--      was cancelled 'Duplicate checkout detected' (~0.33s alive) → the
--      edge function returned the STALE intent as the "winner" → the app
--      rendered the old order's payment screen and showed the generic
--      "Checkout cancelled" screen. The customer could not order at all.
--
-- This migration is the one-time global cleanup the missing sweep would
-- have done, mirroring its two guarded UPDATEs exactly. It is IDEMPOTENT:
-- re-running (or applying after the edge function's new per-customer
-- mini-sweep has already expired some rows) is a no-op for already-clean
-- rows.
--
-- Companion code fix (same incident): supabase/functions/
-- create-gcash-payment-intent/index.ts now runs a per-customer mini-sweep
-- of stale pending intents BEFORE the pending-intent lookup, so this class
-- of collision cannot recur even without pg_cron.
--
-- ⚠️ Environment follow-up: enable the pg_cron extension (Dashboard →
-- Database → Extensions) so the real cluster-wide sweep runs, and
-- register/verify the PayMongo webhook endpoint (the test checkout's
-- payment.paid was never delivered).
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. Expire every payment intent past its window that is still
--    'pending'. (Same UPDATE as step 1 of the cron sweep in
--    20260809000000, which never ran on this DB.)
-- ────────────────────────────────────────────────────────────────
UPDATE public.payment_intents
   SET status = 'expired',
       updated_at = now()
 WHERE status = 'pending'
   AND expires_at < now();

-- ────────────────────────────────────────────────────────────────
-- 2. Cancel orders still 'awaiting_payment' for those expired intents.
--    (Same UPDATE as step 2 of the cron sweep. No stock is held —
--    defer-until-paid — so nothing to release.)
-- ────────────────────────────────────────────────────────────────
UPDATE public.orders o
   SET status = 'cancelled',
       payment_status = 'failed',
       cancellation_reason = 'Payment session expired',
       cancellation_details = 'GCash payment was not completed within the allowed window.',
       cancelled_at = now()
  FROM public.payment_intents pi
 WHERE pi.order_id = o.id
   AND o.status = 'awaiting_payment'
   AND pi.status = 'expired';

-- ────────────────────────────────────────────────────────────────
-- 3. Append-only audit row per expired intent (idempotent — NOT EXISTS
--    guard keeps re-runs and the sweep's own rows from duplicating).
--    Same shape as step 3 of the cron sweep.
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.payment_webhook_events
  (paymongo_event_id, event_type, order_id, payment_intent_id,
   status, livemode, redacted_payload, processed_at)
SELECT 'exp-' || pi.id::text, 'checkout_session.expired', o.id,
       pi.paymongo_payment_intent_id, 'processed', pi.livemode,
       jsonb_build_object(
         'event_id', 'exp-' || pi.id,
         'type', 'checkout_session.expired',
         'resource_id', pi.checkout_session_id,
         'status', 'expired'),
       now()
  FROM public.payment_intents pi
  JOIN public.orders o ON o.id = pi.order_id
 WHERE pi.status = 'expired'
   AND o.status = 'cancelled'
   AND o.payment_status = 'failed'
   AND o.cancellation_reason = 'Payment session expired'
   AND NOT EXISTS (
         SELECT 1
           FROM public.payment_webhook_events e
          WHERE e.paymongo_event_id = 'exp-' || pi.id::text
       );

-- ────────────────────────────────────────────────────────────────
-- 4. Warn (not fail) when pg_cron is absent, so the gap is visible in
--    migration logs. The edge-function mini-sweep covers checkout, but
--    the cluster-wide sweep is still worth enabling.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE WARNING 'pg_cron is not installed — the expire-online-gcash-payments sweep cannot run. Checkout is protected by the per-customer mini-sweep in create-gcash-payment-intent; consider enabling pg_cron (Dashboard → Database → Extensions).';
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run after applying)
-- ────────────────────────────────────────────────────────────────
-- -- No stale pending intents remain:
-- SELECT COUNT(*) FROM public.payment_intents
--  WHERE status = 'pending' AND expires_at < now();   -- expect 0
--
-- -- No orders stuck awaiting payment behind an expired intent:
-- SELECT COUNT(*) FROM public.orders o
--  JOIN public.payment_intents pi ON pi.order_id = o.id
--  WHERE o.status = 'awaiting_payment' AND pi.status = 'expired';  -- expect 0
--
-- -- The incident's test intent is resolved:
-- SELECT id, status FROM public.payment_intents
--  WHERE id = '298a3ab3-93a8-442f-b234-c026ae408bf4';  -- expect 'expired'
--
-- -- Customer 3ee96df2-… can check out again (no pending intent occupies
-- -- the one-pending-per-customer slot):
-- SELECT COUNT(*) FROM public.payment_intents
--  WHERE customer_id = '3ee96df2-64df-40b4-85a0-916a2703a0ec'
--    AND status = 'pending';   -- expect 0
--
-- -- Audit rows appended (one per expired intent, 'exp-' prefixed):
-- SELECT paymongo_event_id, order_id, processed_at
--   FROM public.payment_webhook_events
--  WHERE paymongo_event_id LIKE 'exp-%'
--  ORDER BY processed_at DESC;
