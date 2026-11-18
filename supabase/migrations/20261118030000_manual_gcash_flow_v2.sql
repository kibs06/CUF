-- ══════════════════════════════════════════════════════════════════
-- Migration: Manual GCash flow v2 — schema
-- Date: 2026-11-18
-- Depends on: 20261118020000_add_platform_payment_account.sql
--
-- Purpose: turn the dormant gateway-free GCash flow into the marketplace
--          model: one platform account receives the money, the seller
--          verifies the proof, the admin reconciles the funds, and the
--          seller is paid out at the end of the day.
--
-- What changes, and why:
--
-- 1. orders — a PAID order must stop expiring while it is being verified.
--    New status `payment_under_review` sits between "customer submitted
--    proof" and "seller verified". The 30-minute `payment_confirmation_
--    deadline` now only applies to orders with NO proof (it is the pay
--    window); verification has its own 24h `review_deadline` SLA that
--    never cancels a paid order.
--
-- 2. orders — the audit trail a payout needs: which account the customer
--    was told to pay, when the seller verified, when the admin confirmed
--    the money landed, and whether the payment is flagged.
--
-- 3. orders.order_code — an 8-character code shown to the customer for
--    the GCash note, so one shared inbox can be matched unambiguously.
--
-- 4. gcash_payment_proofs — becomes one row PER ATTEMPT instead of one per
--    order (dropping UNIQUE(order_id)): a customer who mistypes a
--    reference gets up to 3 attempts instead of losing a paid order.
--    Adds the fields a verifier actually checks (payer name, amount paid,
--    paid-at), a SHA-256 of the screenshot (same image cannot back two
--    orders), and the review decision.
--
-- 5. order_payment_events — new event types for the v2 lifecycle.
--
-- 6. admin_notifications — add the 'payment_proof_submitted' type so a
--    proof raises the admin bell. The CHECK is rebuilt by dropping ANY
--    constraint that mentions the older type names, so this is safe
--    whether or not 20261118010000 was applied first.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. orders.status — add 'payment_under_review' (superset CHECK: every
--    previously legal value stays legal, so no existing row or app write
--    is rejected).
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN (
      'pending', 'placed', 'preparing', 'ready', 'delivered',
      'received', 'cancelled', 'cancellation_requested',
      'awaiting_payment', 'payment_conflict',
      'awaiting_payment_confirmation',
      -- Added by 20261110000000 / 20261113000100 / 20261113000400. They MUST
      -- stay: rebuilding the CHECK from an older list would reject every
      -- return/replacement write the app already makes.
      'return_requested', 'replaced', 'replacement_received', 'refunded',
      'payment_under_review'
    ));

COMMENT ON COLUMN public.orders.status IS
  'awaiting_payment_confirmation = manual GCash: order created, stock reserved, customer has payment_confirmation_deadline to pay + submit proof. payment_under_review = proof submitted; money may already be in the platform account, so this NEVER auto-expires — the seller verifies (review_deadline is a 24h SLA only). awaiting_payment / payment_conflict = dormant PayMongo flow.';

-- ────────────────────────────────────────────────────────────────
-- 2. orders — payout + audit columns
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_account_id UUID
    REFERENCES public.platform_payment_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS order_code TEXT,
  ADD COLUMN IF NOT EXISTS review_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS seller_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS seller_verified_by UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS funds_reconciled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS funds_reconciled_by UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_flagged BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payment_flag_reason TEXT;

COMMENT ON COLUMN public.orders.payment_account_id IS
  'The platform_payment_accounts row the customer was told to pay. Kept even after the account is retired so old orders stay explainable.';
COMMENT ON COLUMN public.orders.order_code IS
  'Short human code (8 chars) shown to the customer to put in the GCash note. Unique across orders.';
COMMENT ON COLUMN public.orders.review_deadline IS
  'Verification SLA (24h from proof submission). Advisory only: a lapsed review deadline raises urgency, it never cancels a paid order.';
COMMENT ON COLUMN public.orders.funds_reconciled_at IS
  'Set by an admin after checking the platform GCash statement. Required before the order can be included in a seller payout.';
COMMENT ON COLUMN public.orders.payment_flagged IS
  'Admin flagged the payment (e.g. not found in the statement). Flagged orders are excluded from payouts until cleared.';

-- Unique order code. Existing rows get a code so the index can be created
-- (NULLs would be allowed by a partial index, but then old orders could
-- never be matched; backfill keeps every order addressable).
UPDATE public.orders
   SET order_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
 WHERE order_code IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_order_code
  ON public.orders (order_code)
  WHERE order_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_manual_gcash_review
  ON public.orders (status, created_at DESC)
  WHERE source = 'online' AND payment_method = 'gcash';

-- A per-store index helps the daily payout query and the seller views.
CREATE INDEX IF NOT EXISTS idx_orders_store_paid_online
  ON public.orders (store_id, created_at DESC)
  WHERE payment_status = 'paid' AND source = 'online';

-- ────────────────────────────────────────────────────────────────
-- 3. gcash_payment_proofs — one row per attempt, plus verification data
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.gcash_payment_proofs
  ADD COLUMN IF NOT EXISTS sender_name TEXT,
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS screenshot_hash TEXT,
  ADD COLUMN IF NOT EXISTS attempt_no INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reviewed_by UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- The old UNIQUE(order_id) constraint must go: it is what made a rejected
-- proof unrecoverable. Constraint name differs between environments, so
-- find and drop every single-column unique constraint on order_id.
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'public.gcash_payment_proofs'::regclass
       AND contype = 'u'
       AND conkey = ARRAY[
         (SELECT attnum FROM pg_attribute
           WHERE attrelid = 'public.gcash_payment_proofs'::regclass
             AND attname = 'order_id')
       ]::smallint[]
  LOOP
    EXECUTE format('ALTER TABLE public.gcash_payment_proofs DROP CONSTRAINT %I', c.conname);
  END LOOP;
END
$$;

-- The per-attempt constraint that replaces it. Existing rows are all
-- attempt 1, so this is satisfied without touching data.
DROP INDEX IF EXISTS public.uq_gcash_payment_proofs_order_attempt;
CREATE UNIQUE INDEX uq_gcash_payment_proofs_order_attempt
  ON public.gcash_payment_proofs (order_id, attempt_no);

-- At most ONE proof per order may await review (prevents stacking).
DROP INDEX IF EXISTS public.uq_gcash_payment_proofs_one_pending;
CREATE UNIQUE INDEX uq_gcash_payment_proofs_one_pending
  ON public.gcash_payment_proofs (order_id)
  WHERE status = 'pending';

-- The same screenshot may not back two different orders/attempts. Partial:
-- legacy rows have no hash and are exempt.
DROP INDEX IF EXISTS public.uq_gcash_payment_proofs_screenshot_hash;
CREATE UNIQUE INDEX uq_gcash_payment_proofs_screenshot_hash
  ON public.gcash_payment_proofs (screenshot_hash)
  WHERE screenshot_hash IS NOT NULL;

ALTER TABLE public.gcash_payment_proofs
  DROP CONSTRAINT IF EXISTS chk_gcash_payment_proofs_status;
ALTER TABLE public.gcash_payment_proofs
  ADD CONSTRAINT chk_gcash_payment_proofs_status
    CHECK (status IN ('pending', 'verified', 'rejected'));

ALTER TABLE public.gcash_payment_proofs
  DROP CONSTRAINT IF EXISTS chk_gcash_payment_proofs_attempt;
ALTER TABLE public.gcash_payment_proofs
  ADD CONSTRAINT chk_gcash_payment_proofs_attempt
    CHECK (attempt_no BETWEEN 1 AND 3);

ALTER TABLE public.gcash_payment_proofs
  DROP CONSTRAINT IF EXISTS chk_gcash_payment_proofs_amount;
ALTER TABLE public.gcash_payment_proofs
  ADD CONSTRAINT chk_gcash_payment_proofs_amount
    CHECK (amount_paid IS NULL OR amount_paid > 0);

COMMENT ON COLUMN public.gcash_payment_proofs.attempt_no IS
  'Attempt number (1..3). A rejected proof no longer cancels the order: the customer may resubmit up to 3 times.';
COMMENT ON COLUMN public.gcash_payment_proofs.status IS
  'pending = awaiting seller review; verified = seller accepted; rejected = seller rejected with a reason (order returns to the customer for another attempt).';
COMMENT ON COLUMN public.gcash_payment_proofs.screenshot_hash IS
  'SHA-256 of the uploaded image bytes, computed client-side. UNIQUE when present, so one screenshot cannot substantiate two orders.';
COMMENT ON TABLE public.gcash_payment_proofs IS
  'Proof of payment for a manual GCash order, one row per ATTEMPT (max 3). reference_number stays UNIQUE platform-wide; screenshot_hash is UNIQUE when present. Written only by the submit RPC.';

-- ────────────────────────────────────────────────────────────────
-- 4. order_payment_events — v2 lifecycle types
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.order_payment_events
  DROP CONSTRAINT IF EXISTS order_payment_events_event_type_check;

ALTER TABLE public.order_payment_events
  ADD CONSTRAINT order_payment_events_event_type_check
    CHECK (event_type IN (
      'created', 'proof_submitted', 'confirmed', 'rejected', 'expired',
      'cancelled_by_customer',
      'resubmitted', 'seller_verified', 'admin_verified',
      'flagged', 'unflagged', 'funds_reconciled'
    ));

COMMENT ON TABLE public.order_payment_events IS
  'Append-only payment lifecycle log. v2 adds resubmitted / seller_verified / admin_verified / flagged / unflagged / funds_reconciled. actor_id = the user who acted (NULL = automated sweep). Written only by SECURITY DEFINER RPCs.';

-- ────────────────────────────────────────────────────────────────
-- 5. admin_notifications — allow the proof-submitted notice
--    Rebuilt defensively: drop ANY constraint mentioning the known type
--    names, then add one containing all of them.
-- ────────────────────────────────────────────────────────────────
DO $$
DECLARE
  c record;
BEGIN
  -- This migration is documented to run after 20261118000000, but a hand-run
  -- SQL editor session can arrive in any order. Skipping is safe: the proof
  -- RPC that writes the bell wraps its insert in an exception handler, so a
  -- missing table costs the notice, never the payment.
  IF to_regclass('public.admin_notifications') IS NULL THEN
    RAISE NOTICE 'admin_notifications absent — its type CHECK was skipped';
    RETURN;
  END IF;

  FOR c IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'public.admin_notifications'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%business_docs_resubmitted%'
  LOOP
    EXECUTE format('ALTER TABLE public.admin_notifications DROP CONSTRAINT %I', c.conname);
  END LOOP;

  ALTER TABLE public.admin_notifications
    ADD CONSTRAINT admin_notifications_type_check
      CHECK (type IN (
        'business_docs_resubmitted',
        'payment_mode_mismatch',
        'payment_proof_submitted'
      ));
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--  WHERE conrelid = 'public.orders'::regclass AND contype = 'c';
-- SELECT count(*) FROM public.orders WHERE order_code IS NULL;   -- expect 0
-- SELECT indexname FROM pg_indexes
--  WHERE tablename = 'gcash_payment_proofs';
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint
--  WHERE conrelid = 'public.admin_notifications'::regclass AND contype = 'c';
