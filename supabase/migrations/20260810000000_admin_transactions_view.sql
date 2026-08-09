-- ══════════════════════════════════════════════════════════════════
-- Migration: Admin transactions view — payment table columns + admin RLS
-- Date: 2026-08-10
-- Status: PROPOSED — stop for review before applying or building the UI.
--
-- Purpose: Support the admin portal's read-only GCash/PayMongo
--          Transactions view (docs/AI/ADMIN_GCASH_TRANSACTIONS_PROMPT.md).
--          Adds the columns the view needs and admin-only SELECT
--          policies on the payment tables. This migration is strictly
--          additive and changes NO payment state semantics:
--
--   • payment_intents stays read-only for the client role (existing
--     "Customers can read own payment intents" policy unchanged; new
--     admin SELECT is additive).
--   • payment_webhook_events stays append-only for the client role
--     (it has ZERO client policies today — the new admin SELECT is the
--     only addition).
--   • The webhook (service role) remains the sole writer of payment
--     status. Nothing here creates a client write path.
--
-- DEPENDENCY (IMPLEMENTED alongside this migration in
-- supabase/functions/gcash-webhook/index.ts + _shared/paymongo.ts):
-- the webhook persists paymongo_fee_amount / gcash_reference_number from
-- the payment.paid payload (extractPaymongoFeePesos /
-- extractGcashReference) at every intent-success site. Until PayMongo
-- actually reports them, the admin UI shows "—" (never fabricated
-- values). See the webhook delta below.
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. payment_intents — new columns for the admin view
--    GUARDED: table comes from 20260808120000 (attempt #4). No-op with
--    a notice where it is missing.
--    • paymongo_fee_amount — PayMongo's ACTUAL fee for the transaction
--      (sum of payments[].attributes.fees[].amount, converted to ₱),
--      written by the webhook on payment.paid. NULL = PayMongo has not
--      reported it yet → UI must show "—".
--      NOTE: distinct from the existing fee_amount, which is the
--      server-computed Model B surcharge charged to the customer.
--    • net_amount — what the platform actually nets after PayMongo's
--      cut: amount − paymongo_fee_amount. STORED generated column so
--      the value is always consistent and PostgREST returns it ready.
--      While paymongo_fee_amount is NULL, net_amount equals amount; the
--      UI must only display net when paymongo_fee_amount IS NOT NULL.
--    • gcash_reference_number — PayMongo's e-wallet reference for the
--      payment when the payload exposes it (payment_method_details);
--      NULL otherwise. The online flow does not use the POS-only
--      orders.gcash_reference_number.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF to_regclass('public.payment_intents') IS NULL THEN
    RAISE NOTICE 'payment_intents not found — §1 skipped (apply 20260808120000_add_online_gcash_payments.sql first).';
    RETURN;
  END IF;

  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS paymongo_fee_amount    NUMERIC(12,2);

  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS gcash_reference_number TEXT;

  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS net_amount NUMERIC(12,2)
      GENERATED ALWAYS AS (amount - COALESCE(paymongo_fee_amount, 0)) STORED;

  COMMENT ON COLUMN public.payment_intents.paymongo_fee_amount IS
    'PayMongo''s actual fee for this transaction (from the payment.paid payload fees, in ₱), written by the gcash-webhook. NULL until PayMongo reports it. Distinct from fee_amount (the Model B surcharge charged to the customer).';
  COMMENT ON COLUMN public.payment_intents.gcash_reference_number IS
    'E-wallet reference number from the PayMongo payment (payment_method_details), when exposed. NULL if not available.';
  COMMENT ON COLUMN public.payment_intents.net_amount IS
    'Platform net after PayMongo''s fee: amount − paymongo_fee_amount. Meaningful only when paymongo_fee_amount is set.';

  COMMENT ON TABLE public.payment_intents IS
    'One row per online GCash checkout attempt (PayMongo Checkout Session or Payment Intent). amount includes the Model B GCash fee. Status transitions are server-side only (edge functions); the client role can only SELECT its own rows. Admins may SELECT all rows (read-only view).';
END
$$;

-- ────────────────────────────────────────────────────────────────
-- 2. RLS — admin SELECT only. No admin INSERT/UPDATE/DELETE on
--    payment_intents, and nothing at all on payment_webhook_events.
--    Follows the exact pattern of the existing admin policies
--    (profiles / orders / products): call public.is_admin() (the
--    recursion-free SECURITY DEFINER helper from migration
--    20260809120000_fix_profiles_rls_recursion.sql, which runs BEFORE
--    this one) instead of inlining a profiles subquery.
-- ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admins can read all payment intents"
  ON public.payment_intents;
CREATE POLICY "Admins can read all payment intents"
  ON public.payment_intents FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can read all payment webhook events"
  ON public.payment_webhook_events;
CREATE POLICY "Admins can read all payment webhook events"
  ON public.payment_webhook_events FOR SELECT
  USING (public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- ════════════════════════════════════════════════════════════════
-- WEBHOOK DELTA (IMPLEMENTED in this change set):
-- supabase/functions/_shared/paymongo.ts: added
--   • extractPaymongoFeePesos(event): sum of payments[].attributes.fees[]
--     (each {type, amount} in centavos) → ₱ (amount/100), null when
--     absent. Only PAYMENT events carry fees — always null for
--     payment.failed / expiry / cancel audit rows.
--   • extractGcashReference(event): payment_method_details e-wallet ref
--     (gcash.ref / ewallet.ref), null when absent.
-- supabase/functions/gcash-webhook/index.ts: feeFields = { paymongo_fee_amount,
--   gcash_reference_number } (only present fields) is spread into the
--   payment_intents UPDATE at all four intent-success sites (success,
--   amount_mismatch, stock_conflict, no-snapshot). Empty spreads on
--   retries leave previously stored values untouched.
-- ════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'payment_intents'
--     AND column_name IN ('paymongo_fee_amount','gcash_reference_number','net_amount');
--
-- -- As a NON-admin authenticated user (customer/seller): expect ZERO rows.
-- SET ROLE authenticated;
-- SELECT count(*) FROM public.payment_intents;            -- expect 0
-- SELECT count(*) FROM public.payment_webhook_events;     -- expect 0 (RLS: no policy)
-- RESET ROLE;
--
-- -- As an admin: expect the expected rows (and that writes stay denied).
-- SELECT pi.id, pi.amount, pi.fee_amount, pi.paymongo_fee_amount, pi.net_amount,
--        pi.status, o.id AS order_id, s.name AS store, p.full_name AS customer
-- FROM public.payment_intents pi
-- JOIN public.orders o ON o.id = pi.order_id
-- JOIN public.stores s ON s.id = o.store_id
-- JOIN public.profiles p ON p.id = pi.customer_id
-- ORDER BY pi.created_at DESC;
--
-- -- Denied-write smoke test (admin): must FAIL (no write policy).
-- -- UPDATE public.payment_intents SET status = 'succeeded' WHERE false;
