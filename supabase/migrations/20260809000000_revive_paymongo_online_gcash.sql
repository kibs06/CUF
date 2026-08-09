-- ══════════════════════════════════════════════════════════════════
-- Migration: Revive PayMongo online GCash — schema + RPCs (attempt #6)
-- Date: 2026-08-09
-- Status: APPROVED at the review gate, then revised per code review:
--         (a) guarded §2/§7 so it applies cleanly on any DB history,
--         (b) expiry sweep now writes an audit row + notifies the
--             customer, (c) added cancel_my_pending_payment_intent for
--             §8.4 (customer self-service), (d) tightened fee CHECK,
--             (e) set_payment_fee_config takes both args explicitly.
--
-- Purpose: Replace the gateway-free direct GCash online flow (attempt
--          #5, currently LIVE) with a real gateway flow: PayMongo
--          redirect-based GCash, order marked paid ONLY by a
--          signature-verified webhook. This migration revives and
--          extends the DORMANT attempt-#4 PayMongo schema; it does not
--          delete any attempt-#5 object (destructive migrations are
--          avoided; the direct flow is formally deprecated instead).
--
-- ══════════════════════════════════════════════════════════════════
-- DECISIONS (confirmed with the human on 2026-08-09, where noted)
-- ══════════════════════════════════════════════════════════════════
--
-- 1. GATEWAY + API — PayMongo CHECKOUT SESSIONS (confirmed at review).
--    One call → PayMongo-hosted page handles the GCash handoff, with
--    explicit success_url/cancel_url redirects; webhook events
--    checkout_session.payment.paid (+ payment.paid/payment.failed
--    defensively). Chosen over the manual Payment Intents + attach
--    flow (attempt #4) which is what erroring "payment provider
--    unavailable" in prod, and because PayMongo now recommends it and
--    builds it for pass-on fees.
--
-- 2. REDIRECT UX (human asked me to research + recommend) — SYSTEM
--    BROWSER, not in-app webview. PayMongo's hosted checkout hands off
--    to GCash via the gcash:// custom scheme; mobile WebViews do not
--    intercept custom schemes by default, which strands the customer.
--    url_launcher (already a dependency) opens the checkout_url; the
--    app returns via its deep link and then POLLS get-payment-status —
--    never trusts the redirect.
--
-- 3. FEE — Model B (surcharge passed to the customer, CONFIRMED).
--    The customer is charged order_total + a GCash fee so the seller
--    nets the full order total. The fee is computed SERVER-SIDE from
--    payment_fee_config (rate = data, never hardcoded) and DISCLOSED
--    at checkout as a separate line item.
--    Formula (solves for the charge that covers the fee exactly):
--      r_total   = (rate_bps/10000) * (1 + vat_bps/10000)   [all-in rate]
--      charged   = ceil_to_cent( order_total / (1 - r_total) )
--      fee       = charged - order_total
--    Baseline: ~2.23% + 12% VAT (~2.5% all-in); verify against the
--    PayMongo pricing page before go-live and update the config row.
--    orders.total_amount is UNCHANGED in meaning (products + delivery,
--    the seller-facing revenue basis); the surcharge lives in the new
--    gcash_fee_* columns; the amount sent to PayMongo = total + fee
--    (mirrored on payment_intents.amount). Existing seller revenue
--    queries (payment_status='paid' + total_amount) keep working and
--    are NOT inflated by the fee.
--
-- 4. STOCK — DEFER-UNTIL-PAID (reuses attempt #4's items_snapshot).
--    order_items are NOT inserted at intent creation; stock is
--    untouched until the verified webhook materializes them on
--    payment.paid (the existing decrement trigger then rejects
--    oversell). No reservation → nothing to release on failure/expiry.
--
-- 5. EXPIRY — 15 MINUTES (CONFIRMED). payment_intents.expires_at =
--    now() + 15 min at creation (set by the edge function). The
--    pg_cron job 'expire-online-gcash-payments' marks expired intents,
--    cancels their awaiting_payment orders, writes an append-only
--    audit row, and notifies the customer (added in this revision).
--
-- 6. STATUS SEMANTICS (the 'pending' meanings, documented):
--    • orders.status = 'awaiting_payment'          → LIVE (PayMongo
--      online): created, charged only by the verified webhook.
--    • orders.status = 'pending'                   → paid + in the
--      normal seller fulfillment pipeline.
--    • orders.status = 'awaiting_payment_confirmation' → DORMANT
--      (attempt #5 direct flow; stays legal in the CHECK, unwired).
--    • orders.status = 'payment_conflict'          → LIVE (PayMongo):
--      money captured but cannot fulfill — manual review, never
--      auto-deleted.
--    • orders.payment_status 'pending' → 'paid' is set ONLY by the
--      verified webhook (service role); 'failed' on payment.failed /
--      expiry / customer self-cancel. The POS manual-confirm flow is
--      untouched and still uses its own payment_status 'pending' →
--      'paid' via the seller's tap on source='pos' orders; the two
--      meanings never collide (POS has no 'awaiting_payment' orders).
--
-- 7. DORMANT ASSETS (attempt #5 direct flow) — KEPT, formally
--    deprecated in comments (guarded so this migration never errors on
--    a DB missing them): gcash_payment_proofs, order_payment_events,
--    uq_orders_one_awaiting_payment_confirmation_per_customer, the
--    five direct-flow RPCs, the payment-proofs bucket. Nothing is
--    deleted here; the Flutter UI stops calling them (separate step).
--
-- 8. REUSE (attempt #2/#4 dormant columns) — gcash_transaction_id and
--    payment_verified_at are written by the webhook on payment.paid
--    (pay_xxx id + confirmation timestamp), exactly as attempt #4 did.
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. orders — Model B fee snapshot columns
--    total_amount stays = products + delivery (seller revenue basis).
--    The customer is charged total_amount + gcash_fee_amount.
--    Snapshots make the fee on every order reconstructible for audits
--    and disputes even if the config rate later changes.
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gcash_fee_amount   NUMERIC(12,2);
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gcash_fee_rate_bps INT;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gcash_fee_vat_bps  INT;

COMMENT ON COLUMN public.orders.gcash_fee_amount IS
  'Model B surcharge charged to the customer on top of total_amount to cover the PayMongo GCash fee. Set at payment-intent creation (server-side). Customer charged = total_amount + gcash_fee_amount; seller nets total_amount.';
COMMENT ON COLUMN public.orders.gcash_fee_rate_bps IS
  'Snapshot of payment_fee_config.rate_bps at intent creation (fee rate, VAT-exclusive, in basis points).';
COMMENT ON COLUMN public.orders.gcash_fee_vat_bps IS
  'Snapshot of payment_fee_config.vat_bps at intent creation (VAT rate on the fee, in basis points).';

-- Refresh the status comment to reflect the revived PayMongo flow.
COMMENT ON COLUMN public.orders.status IS
  'awaiting_payment = LIVE (PayMongo online GCash): created, charged only by the signature-verified webhook. payment_conflict = LIVE (PayMongo): money captured but cannot fulfill normally — manual review. awaiting_payment_confirmation = DORMANT (attempt #5 gateway-free direct flow; no wired UI calls it). pending = paid and in the normal seller pipeline.';

-- ────────────────────────────────────────────────────────────────
-- 2. payment_intents — additive columns for Checkout Sessions + fee
--    GUARDED: the table comes from attempt #4 (20260808120000); on a
--    DB where that migration was never applied, this section is a
--    no-op with a notice instead of an error.
--    • checkout_session_id (cs_xxx) for the Checkout Sessions API —
--      paymongo_payment_intent_id (pi_xxx) is backfilled by the
--      webhook from the embedded payment_intent.
--    • fee_amount / fee_rate_bps — Model B audit snapshot on the
--      intent itself (mirrors the orders columns).
--    payment_intents.amount = the amount actually charged to the
--    customer = order_total + fee (what the webhook must verify).
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF to_regclass('public.payment_intents') IS NULL THEN
    RAISE NOTICE 'payment_intents not found — §2 skipped (apply 20260808120000_add_online_gcash_payments.sql first).';
    RETURN;
  END IF;

  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS checkout_session_id TEXT;

  CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_intents_checkout_session
    ON public.payment_intents(checkout_session_id)
    WHERE checkout_session_id IS NOT NULL;

  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS fee_amount NUMERIC(12,2);
  ALTER TABLE public.payment_intents
    ADD COLUMN IF NOT EXISTS fee_rate_bps INT;

  COMMENT ON COLUMN public.payment_intents.checkout_session_id IS
    'PayMongo Checkout Session id (cs_xxx) when using the Checkout Sessions API; NULL for the manual Payment Intents flow (pi_xxx lives in paymongo_payment_intent_id).';
  COMMENT ON COLUMN public.payment_intents.fee_amount IS
    'Model B surcharge included in amount. amount = order total + fee.';
  COMMENT ON COLUMN public.payment_intents.fee_rate_bps IS
    'Fee rate snapshot (basis points, VAT-exclusive) used to compute fee_amount.';

  COMMENT ON TABLE public.payment_intents IS
    'One row per online GCash checkout attempt (PayMongo Checkout Session or Payment Intent). amount includes the Model B GCash fee. Status transitions are server-side only (edge functions); the client role can only SELECT its own rows.';
END
$$;

-- ────────────────────────────────────────────────────────────────
-- 3. payment_fee_config — the source of truth for the GCash fee rate
--    Singleton row (id = 1). RATE IS DATA, NOT CODE — the checkout
--    fee display and the intent-creation edge function both read this,
--    so a gateway rate change is a config update, not a deploy.
--    CHECK tightened to rate_bps <= 8000 (80%): any higher all-in rate
--    would exceed 100% after VAT and brick checkout; the runtime guard
--    remains as a second line of defense.
--    RLS: authenticated users may READ (the fee is shown at checkout);
--    writes only via the admin RPC in §5 — clients can never change
--    what they are charged.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_fee_config (
  id         INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),   -- singleton
  gateway    TEXT NOT NULL DEFAULT 'paymongo_gcash',
  rate_bps   INT NOT NULL CHECK (rate_bps BETWEEN 1 AND 8000),  -- fee %, VAT-exclusive, in basis points
  vat_bps    INT NOT NULL DEFAULT 1200 CHECK (vat_bps >= 0),    -- VAT on the fee, in basis points
  active     BOOLEAN NOT NULL DEFAULT true,
  updated_by UUID REFERENCES public.profiles(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  note       TEXT
);

COMMENT ON TABLE public.payment_fee_config IS
  'Singleton (id=1) GCash fee configuration. rate_bps = PayMongo published rate (VAT-exclusive) in basis points; vat_bps = VAT on the fee. The all-in rate is rate_bps/10000 * (1 + vat_bps/10000). Writes are admin-RPC only.';

INSERT INTO public.payment_fee_config (id, gateway, rate_bps, vat_bps, note)
VALUES (1, 'paymongo_gcash', 223, 1200,
        'Baseline from PayMongo published GCash rate (~2.23% + 12% VAT on the fee). VERIFY against the live PayMongo pricing page before go-live and update here — never in code.')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.payment_fee_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone signed in can read the fee config" ON public.payment_fee_config;
CREATE POLICY "Anyone signed in can read the fee config"
  ON public.payment_fee_config FOR SELECT
  USING (auth.role() = 'authenticated');

-- No INSERT/UPDATE/DELETE policies — writes go through the admin RPC.

-- ────────────────────────────────────────────────────────────────
-- 4. get_gcash_fee(p_subtotal) — checkout fee display (customer, JWT)
--    Returns the Model B breakdown for a given order subtotal so the
--    checkout screen can show the GCash fee as its own line item BEFORE
--    the customer submits. DISPLAY-ONLY: the authoritative computation
--    happens inside the intent-creation edge function from server-side
--    prices. Same formula by construction:
--      r_total = (rate_bps/10000) * (1 + vat_bps/10000)
--      charged = ceil_to_cent(subtotal / (1 - r_total))
--      fee     = charged - subtotal
--    ceil() in centavos so the surcharge never under-collects the fee.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_gcash_fee(
  p_subtotal numeric
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate_bps   int;
  v_vat_bps    int;
  v_r_total    numeric;
  v_charged    numeric;
  v_fee        numeric;
BEGIN
  IF p_subtotal IS NULL OR p_subtotal <= 0 THEN
    RAISE EXCEPTION 'Subtotal must be greater than zero';
  END IF;

  SELECT rate_bps, vat_bps
    INTO v_rate_bps, v_vat_bps
    FROM public.payment_fee_config
   WHERE id = 1 AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GCash fee is not configured. Please contact support.';
  END IF;

  v_r_total := (v_rate_bps::numeric / 10000) * (1 + v_vat_bps::numeric / 10000);
  IF v_r_total >= 1 THEN
    RAISE EXCEPTION 'GCash fee configuration is invalid (all-in rate >= 100%%)';
  END IF;

  -- ceil to the next centavo: charged = subtotal / (1 - r_total)
  v_charged := ceil(p_subtotal * 100 / (1 - v_r_total)) / 100;
  v_fee     := round(v_charged - p_subtotal, 2);

  RETURN jsonb_build_object(
    'base',          round(p_subtotal, 2),
    'rate_bps',      v_rate_bps,
    'vat_bps',       v_vat_bps,
    'effective_rate', round(v_r_total, 6),
    'fee_amount',    v_fee,
    'total_charged', v_charged
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_gcash_fee(numeric) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_gcash_fee(numeric) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 5. set_payment_fee_config(p_rate_bps, p_vat_bps) — admin only
--    The single write path for the fee rate. Both args are explicit
--    (no DEFAULT — avoids PostgREST default-arg resolution quirks).
--    Requires the caller's profile role = 'admin' (explicit check
--    inside, not just RLS).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_payment_fee_config(
  p_rate_bps int,
  p_vat_bps  int
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only admins can change the GCash fee configuration';
  END IF;
  IF p_rate_bps < 1 OR p_rate_bps > 8000 THEN
    RAISE EXCEPTION 'rate_bps must be between 1 and 8000';
  END IF;
  IF p_vat_bps < 0 THEN
    RAISE EXCEPTION 'vat_bps cannot be negative';
  END IF;

  UPDATE public.payment_fee_config
     SET rate_bps = p_rate_bps,
         vat_bps  = p_vat_bps,
         updated_by = auth.uid(),
         updated_at = now()
   WHERE id = 1;

  RETURN jsonb_build_object('updated', true, 'rate_bps', p_rate_bps, 'vat_bps', p_vat_bps);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_payment_fee_config(int, int) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.set_payment_fee_config(int, int) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 6. cancel_my_pending_payment_intent(p_order_id) — customer self-service
--    §8.4: a customer who wants to abandon/replace a pending GCash
--    checkout (different cart, changed mind, etc.) can cancel it
--    instead of waiting up to 15 minutes for expiry.
--    SAFE by construction: while status='awaiting_payment' no money has
--    been captured and (defer-until-paid) no stock is held.
--    Guarded: only the order's owner; only a still-pending intent; only
--    an awaiting-payment order. If the webhook already finalized
--    (money moved), the intent UPDATE matches 0 rows → returns false,
--    order untouched.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_my_pending_payment_intent(
  p_order_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.orders
    WHERE id = p_order_id AND customer_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  UPDATE public.payment_intents
     SET status = 'cancelled', updated_at = now()
   WHERE order_id = p_order_id
     AND status = 'pending'
     AND customer_id = auth.uid();
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN false; -- already resolved (paid/failed/expired) — nothing to cancel
  END IF;

  UPDATE public.orders
     SET status = 'cancelled',
         payment_status = 'failed',
         cancellation_reason = 'Cancelled by customer',
         cancellation_details = 'The GCash checkout was cancelled before payment was completed.',
         cancelled_at = now()
   WHERE id = p_order_id
     AND status = 'awaiting_payment'
     AND customer_id = auth.uid();

  -- Append-only audit row (synthetic key, same pattern as the sweep).
  INSERT INTO public.payment_webhook_events
    (paymongo_event_id, event_type, order_id, payment_intent_id, status, redacted_payload, processed_at)
  SELECT 'cancel-' || id::text, 'checkout_session.cancelled', p_order_id,
         paymongo_payment_intent_id, 'processed',
         jsonb_build_object('event_id', 'cancel-' || id, 'type',
                            'checkout_session.cancelled',
                            'resource_id', checkout_session_id,
                            'status', 'cancelled'),
         now()
  FROM public.payment_intents
  WHERE order_id = p_order_id;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_my_pending_payment_intent(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.cancel_my_pending_payment_intent(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 7. Re-ensure the PayMongo expiry sweep cron job
--    'expire-online-gcash-payments' (created by attempt #4) marks
--    payment_intents past expires_at (15 min, set at creation) as
--    expired, cancels their awaiting_payment orders (no stock to
--    release — defer-until-paid), and — NEW in this revision — writes
--    an append-only audit row into payment_webhook_events and notifies
--    the customer, so an abandoned checkout is never silent.
--    The NOT EXISTS guards keep the inserts idempotent across runs.
--    Guarded no-op where the job already exists; re-created on DBs
--    where it was dropped or attempt #4 was never applied.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-online-gcash-payments') THEN
    PERFORM cron.schedule(
      'expire-online-gcash-payments',
      '*/5 * * * *',
      $cron$
        -- 1) Mark payment intents past their window as expired.
        UPDATE public.payment_intents pi
        SET status = 'expired', updated_at = now()
        WHERE pi.status = 'pending'
          AND pi.expires_at < now();

        -- 2) Cancel orders still awaiting payment for those intents.
        --    (No stock is held — defer-until-paid — so nothing to release.)
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

        -- 3) Append-only audit row per expired intent (idempotent).
        INSERT INTO public.payment_webhook_events
          (paymongo_event_id, event_type, order_id, payment_intent_id,
           status, livemode, redacted_payload, processed_at)
        SELECT 'exp-' || pi.id::text, 'checkout_session.expired', o.id,
               pi.paymongo_payment_intent_id, 'processed', pi.livemode,
               jsonb_build_object('event_id', 'exp-' || pi.id,
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
            SELECT 1 FROM public.payment_webhook_events e
            WHERE e.paymongo_event_id = 'exp-' || pi.id::text
          );

        -- 4) Notify the customer (idempotent — title-scoped guard).
        INSERT INTO public.notifications (user_id, order_id, category, title, message)
        SELECT o.customer_id, o.id, 'returns', 'Payment session expired',
               'Order #' || left(o.id::text, 8) || ' — the GCash payment was not completed within the allowed window. No charge was made; you can place a new order anytime.'
        FROM public.orders o
        JOIN public.payment_intents pi ON pi.order_id = o.id
        WHERE pi.status = 'expired'
          AND o.status = 'cancelled'
          AND o.payment_status = 'failed'
          AND o.cancellation_reason = 'Payment session expired'
          AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.order_id = o.id AND n.category = 'returns'
              AND n.title = 'Payment session expired'
          );
      $cron$
    );
    RAISE NOTICE 'Scheduled pg_cron job: expire-online-gcash-payments (every 5 min)';
  ELSE
    RAISE NOTICE 'pg_cron unavailable or job already exists — expiry enforced by the app-side sweep call / existing job. NOTE: if an older job exists, update it to include the audit-row + notification steps from §7.';
  END IF;
EXCEPTION
  WHEN undefined_table OR insufficient_privilege OR undefined_function THEN
    RAISE NOTICE 'pg_cron unavailable — expiry enforced by app-side calls. Payment finalization is unaffected (webhook-driven).';
END
$$;

-- ────────────────────────────────────────────────────────────────
-- 8. Formal deprecation notes on the attempt-#5 (gateway-free direct)
--    flow's objects — kept, not deleted (no destructive migration).
--    GUARDED: comments are only applied where the objects exist, so
--    this never errors on a DB with a different migration history.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF to_regclass('public.gcash_payment_proofs') IS NOT NULL THEN
    EXECUTE 'COMMENT ON TABLE public.gcash_payment_proofs IS ''DORMANT (attempt #5 gateway-free direct GCash; replaced by the PayMongo online flow). No wired UI writes these anymore. Kept for history — do not delete without a documented migration.''';
  END IF;
  IF to_regclass('public.order_payment_events') IS NOT NULL THEN
    EXECUTE 'COMMENT ON TABLE public.order_payment_events IS ''DORMANT for the direct-flow events (created/proof_submitted/confirmed/rejected/expired). The PayMongo flow uses payment_webhook_events for its audit trail. Kept for history.''';
  END IF;
  IF to_regprocedure('public.create_gcash_checkout(jsonb,text,jsonb)') IS NOT NULL THEN
    EXECUTE 'COMMENT ON FUNCTION public.create_gcash_checkout(jsonb,text,jsonb) IS ''DORMANT (attempt #5 gateway-free direct GCash). Not called by any wired UI. Kept for history.''';
  END IF;
  IF to_regprocedure('public.submit_gcash_proof(uuid,text,text)') IS NOT NULL THEN
    EXECUTE 'COMMENT ON FUNCTION public.submit_gcash_proof(uuid,text,text) IS ''DORMANT (attempt #5). Kept for history.''';
  END IF;
  IF to_regprocedure('public.confirm_gcash_payment(uuid)') IS NOT NULL THEN
    EXECUTE 'COMMENT ON FUNCTION public.confirm_gcash_payment(uuid) IS ''DORMANT (attempt #5). Kept for history.''';
  END IF;
  IF to_regprocedure('public.reject_gcash_payment(uuid,text)') IS NOT NULL THEN
    EXECUTE 'COMMENT ON FUNCTION public.reject_gcash_payment(uuid,text) IS ''DORMANT (attempt #5). Kept for history.''';
  END IF;
  IF to_regprocedure('public.expire_overdue_gcash_orders()') IS NOT NULL THEN
    EXECUTE 'COMMENT ON FUNCTION public.expire_overdue_gcash_orders() IS ''DORMANT (attempt #5). Kept for history.''';
  END IF;
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'orders'
--     AND column_name IN ('gcash_fee_amount','gcash_fee_rate_bps','gcash_fee_vat_bps');
--
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'payment_intents'
--     AND column_name IN ('checkout_session_id','fee_amount','fee_rate_bps');
--
-- SELECT * FROM public.payment_fee_config;
-- SELECT public.get_gcash_fee(250);
--   -- expect: rate_bps=223, vat_bps=1200, fee_amount≈6.41, total_charged≈256.41
--
-- SELECT proname, prosecdef FROM pg_proc
--   WHERE proname IN ('get_gcash_fee','set_payment_fee_config',
--                     'cancel_my_pending_payment_intent');
--
-- SELECT jobname FROM cron.job WHERE jobname = 'expire-online-gcash-payments';
--
-- SELECT has_table_privilege('authenticated', 'public.payment_fee_config', 'SELECT');
--   -- expect: true (read-only fee display); no write privilege.
--
-- -- RLS spot check (attempt as a customer): cancel someone else's order
-- -- via the RPC must be denied; your own pending order must cancel.
