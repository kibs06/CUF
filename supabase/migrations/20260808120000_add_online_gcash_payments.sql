-- ══════════════════════════════════════════════════════════════════
-- Migration: Real online GCash payments (attempt #3)
-- Date: 2026-08-08
-- Purpose: Make online GCash checkout a real redirect-based payment
--          flow (PayMongo Payment Intents, e-wallet `gcash` type).
--          The order is created in a new `awaiting_payment` state and
--          only becomes `pending` (enters the seller pipeline) after a
--          SIGNATURE-VERIFIED PayMongo webhook confirms payment.
--
-- Design decisions (see docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md):
--   • Stock is NOT touched at intent creation (defer-until-paid).
--     order_items are inserted only by the webhook after payment.paid,
--     which is what triggers the existing stock-decrement trigger.
--   • The client NEVER writes payment status. Only the webhook (service
--     role) finalizes orders.
--   • Reuses the dormant attempt-#2 columns on orders:
--       gcash_transaction_id  ← PayMongo payment id (pay_xxx)
--       payment_verified_at   ← webhook confirmation timestamp
--     The online flow now writes them (previously dead columns).
--   • orders.gcash_reference_number stays owned by the POS manual flow
--     (seller-typed ref #) — the online flow does NOT touch it.
--
-- New statuses:
--   orders.status:          'awaiting_payment' (created, not yet paid),
--                           'payment_conflict' (money captured but cannot
--                           fulfill: stock conflict / amount mismatch —
--                           needs manual review, NEVER auto-deleted)
--   orders.payment_status:  'failed' (payment failed or expired)
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. orders.status — add 'awaiting_payment' + 'payment_conflict'
--    (superset of every status ever allowed, so no existing rows or
--    app writes are rejected)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN (
      'pending', 'placed', 'preparing', 'ready', 'delivered',
      'received', 'cancelled', 'cancellation_requested',
      'awaiting_payment', 'payment_conflict'
    ));

COMMENT ON COLUMN public.orders.status IS
  'awaiting_payment = created, GCash payment not yet confirmed by webhook. payment_conflict = money captured but order cannot be fulfilled normally (stock conflict/amount mismatch) — manual review required.';

-- ────────────────────────────────────────────────────────────────
-- 2. orders.payment_status — add 'failed'
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_payment_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_payment_status_check
    CHECK (payment_status IN ('paid', 'unpaid', 'pending', 'failed'));

COMMENT ON COLUMN public.orders.payment_status IS
  'paid = verified payment. pending = awaiting verification. unpaid = cash on pickup. failed = payment failed/expired. Only the server-side webhook may set paid.';

-- ────────────────────────────────────────────────────────────────
-- 3. orders.items_snapshot — line items recorded at intent creation
--    (stock is deferred; order_items rows are materialized from this
--    snapshot by the webhook after payment.paid)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS items_snapshot JSONB;

COMMENT ON COLUMN public.orders.items_snapshot IS
  '[{product_id, product_name, size, quantity, unit_price}] captured at payment-intent creation with server-side prices. Materialized into order_items by the webhook once payment is confirmed.';

-- ────────────────────────────────────────────────────────────────
-- 4. payment_intents — one row per PayMongo payment intent
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_intents (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- ⚠️ LIVE DB uses UUID for orders.id (schema.sql says BIGINT — schema.sql is stale).
  order_id                  UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  -- Client-generated UUID sent with the checkout request. UNIQUE per
  -- customer → double-taps / retries cannot create two intents.
  idempotency_key           UUID NOT NULL,
  paymongo_payment_intent_id TEXT,          -- pi_xxx
  paymongo_payment_method_id TEXT,          -- pm_xxx (debug/refund aid)
  client_key                TEXT,           -- scoped to this intent only
  checkout_url              TEXT,           -- next_action.redirect.url
  amount                    NUMERIC(12,2) NOT NULL, -- intended charge (₱)
  currency                  TEXT NOT NULL DEFAULT 'PHP',
  -- Stable fingerprint of the ordered items (sorted "product_id:size:qty"
  -- joined by '|'). Used to detect whether an active pending intent
  -- belongs to the SAME cart being submitted (prevents a customer with a
  -- stale pending checkout from paying for the wrong cart).
  items_fingerprint          TEXT NOT NULL,
  status                    TEXT NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'succeeded', 'failed', 'expired', 'cancelled')),
  livemode                  BOOLEAN NOT NULL DEFAULT false,
  expires_at                TIMESTAMPTZ NOT NULL,
  paid_at                   TIMESTAMPTZ,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (customer_id, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_intents_paymongo_pi
  ON public.payment_intents(paymongo_payment_intent_id)
  WHERE paymongo_payment_intent_id IS NOT NULL;

-- DB-level guard against two concurrent checkouts for the same customer:
-- at most ONE pending intent per customer, enforced atomically by the
-- database. The app-layer lookup in create-gcash-payment-intent handles
-- sequential double-taps; this index closes the concurrent-request race
-- (two different idempotency keys arriving at once would otherwise create
-- two PayMongo intents and two possible charges).
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_intents_one_pending_per_customer
  ON public.payment_intents(customer_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_payment_intents_order
  ON public.payment_intents(order_id);

CREATE INDEX IF NOT EXISTS idx_payment_intents_customer_status_expiry
  ON public.payment_intents(customer_id, status, expires_at);

COMMENT ON TABLE public.payment_intents IS
  'PayMongo payment intents for online GCash. Status transitions are server-side only.';

-- RLS: a customer may only READ their own payment intents.
-- No INSERT/UPDATE/DELETE policies → the client role can never write
-- payment state. The webhook and intent-creation functions use the
-- service role, which bypasses RLS.
ALTER TABLE public.payment_intents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can read own payment intents" ON public.payment_intents;
CREATE POLICY "Customers can read own payment intents"
  ON public.payment_intents FOR SELECT
  USING (auth.uid() = customer_id);

-- ────────────────────────────────────────────────────────────────
-- 5. payment_webhook_events — append-only audit log + idempotency gate
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id                  BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  paymongo_event_id   TEXT NOT NULL UNIQUE,   -- evt_xxx — idempotency key
  event_type          TEXT NOT NULL,
  order_id            UUID REFERENCES public.orders(id) ON DELETE SET NULL,  -- live DB: orders.id is UUID
  payment_intent_id   TEXT,                   -- pi_xxx (denormalized for audit)
  status              TEXT NOT NULL DEFAULT 'received'
                        CHECK (status IN (
                          'received', 'processing', 'processed',
                          'skipped_duplicate', 'ignored_unknown',
                          'ignored_stale', 'rejected_signature',
                          'amount_mismatch', 'stock_conflict', 'failed'
                        )),
  livemode            BOOLEAN,
  amount              NUMERIC(12,2),
  redacted_payload    JSONB,                  -- no payment-method details
  received_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events(order_id);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_received
  ON public.payment_webhook_events(received_at DESC);

COMMENT ON TABLE public.payment_webhook_events IS
  'Append-only log of every PayMongo webhook event. paymongo_event_id UNIQUE is the idempotency gate — duplicate deliveries are no-ops. redacted_payload excludes card/wallet/billing fields.';

-- RLS: NO policies → fully locked down. Only the service role (webhook)
-- can read/write it; clients get denied by default.
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────────
-- 6. Expiry sweep — release 'awaiting_payment' orders whose payment
--    window (default 30 min) has lapsed. Runs every 5 minutes via
--    pg_cron if the extension is available; otherwise the documented
--    fallback is an external cron hitting the webhook or a manual run.
--    No stock is held for awaiting_payment orders (defer-until-paid),
--    so this only transitions state — nothing to release.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     -- to_regclass() returns NULL instead of raising 42P01 when the
     -- relation is missing, so a DB without usable pg_cron never fails
     -- this migration (the old `SELECT 1 FROM cron.job` check exploded
     -- at plan time even when the extension was merely listed).
     AND to_regclass('cron.job') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-online-gcash-payments') THEN
    PERFORM cron.schedule(
      'expire-online-gcash-payments',
      '*/5 * * * *',
      $cron$
        -- 1) Mark payment intents past their window as expired
        UPDATE public.payment_intents pi
        SET status = 'expired', updated_at = now()
        WHERE pi.status = 'pending'
          AND pi.expires_at < now();

        -- 2) Cancel orders still awaiting payment for those intents.
        --    status → 'cancelled' is unmapped in the notification
        --    trigger (ELSE branch), so no noisy notifications.
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
      $cron$
    );
    RAISE NOTICE 'Scheduled pg_cron job: expire-online-gcash-payments (every 5 min)';
  ELSE
    RAISE NOTICE 'pg_cron unavailable — expiry sweep NOT scheduled. Fallback: external cron hitting the webhook, or the documented manual run. Payment finalization is unaffected (webhook-driven).';
  END IF;
EXCEPTION
  -- Belt-and-suspenders: any pg_cron-related surprise (missing extension
  -- objects, insufficient privilege on cron schema, etc.) must degrade
  -- to a notice, never fail the migration.
  WHEN undefined_table OR insufficient_privilege OR undefined_function THEN
    RAISE NOTICE 'pg_cron unavailable — expiry sweep NOT scheduled. Fallback: external cron or manual run. Payment finalization is unaffected (webhook-driven).';
END
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT status, count(*) FROM public.orders GROUP BY status;
-- SELECT * FROM public.payment_intents LIMIT 5;
-- SELECT * FROM public.payment_webhook_events LIMIT 5;
-- SELECT cron.job  -- if pg_cron is enabled
