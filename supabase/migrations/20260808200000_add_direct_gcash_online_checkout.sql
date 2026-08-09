-- ══════════════════════════════════════════════════════════════════
-- Migration: Direct (gateway-free) GCash online checkout — SCHEMA
-- Date: 2026-08-08
--
-- Purpose: Replace the PayMongo-based online GCash flow (attempt #4,
--          currently erroring in prod with "payment provider
--          unavailable") with the store's proven POS pattern extended
--          to online checkout: the customer pays the seller's own
--          GCash QR peer-to-peer, submits proof, and the SELLER
--          manually confirms receipt — no payment gateway, no platform
--          cut, no webhook.
--
-- This file is SCHEMA ONLY. The server functions (create-checkout /
-- submit-proof / confirm / reject / expiry sweep) ship as SECURITY
-- DEFINER Postgres RPCs in a follow-up migration after this schema is
-- reviewed (per the task brief's review gate). The Flutter UI lands
-- after the functions.
--
-- Product decisions (confirmed with the human):
--   • Proof screenshot is REQUIRED (stored in a private bucket).
--   • Confirmation deadline: 30 minutes from order creation.
--   • Reference number unique PLATFORM-WIDE (real GCash refs are
--     globally unique per transaction).
--   • At most ONE awaiting-payment-confirmation order per customer
--     (enforced by a partial unique index — atomic, race-proof).
--   • Server layer: Postgres RPCs (SECURITY DEFINER), not edge
--     functions — atomic order+items+deadline+event in one transaction.
--   • The PayMongo flow (awaiting_payment / payment_conflict /
--     payment_intents / payment_webhook_events) stays DORMANT in the
--     repo and in this DB — nothing is deleted, it's just unwired.
--
-- State machine (documented in the architecture doc update):
--   awaiting_payment_confirmation --seller confirms--> pending (pipeline), payment_status='paid'
--        |  (stock reserved at creation)
--        +--seller rejects----------> cancelled, payment_status='failed', stock released
--        +--deadline passes---------> cancelled, payment_status='failed', stock released
--
-- Stock reservation (mechanism decided):
--   • At order creation the create RPC inserts the orders row AND the
--     order_items rows in ONE transaction → the existing
--     decrement_inventory_on_order trigger (SECURITY DEFINER, guards
--     stock >= quantity, raises P0001 'Insufficient stock') decrements
--     stock atomically and rejects oversell — the second customer for
--     the last unit fails cleanly at checkout, order rolled back.
--   • Release (reject/expire) is a DELETE ... RETURNING over
--     order_items that re-increments inventory — exactly-once by
--     construction (a second run deletes 0 rows and increments nothing),
--     serialized by SELECT ... FOR UPDATE on the order row.
--   • Confirm does NOT touch order_items (already inserted) — stock is
--     decremented exactly once, at reservation.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. orders.status — add 'awaiting_payment_confirmation'
--    (superset CHECK: keeps every existing + dormant value legal, so no
--    existing rows or app writes are rejected)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
    CHECK (status IN (
      'pending', 'placed', 'preparing', 'ready', 'delivered',
      'received', 'cancelled', 'cancellation_requested',
      'awaiting_payment', 'payment_conflict',
      'awaiting_payment_confirmation'
    ));

COMMENT ON COLUMN public.orders.status IS
  'awaiting_payment = PayMongo flow, DORMANT (not used by any wired UI). awaiting_payment_confirmation = gateway-free GCash: order created, stock reserved, seller must confirm the customer''s proof of payment before payment_confirmation_deadline. payment_conflict = gateway-only (dormant).';

-- ────────────────────────────────────────────────────────────────
-- 2. orders.payment_confirmation_deadline — when the seller must
--    confirm/reject before the reservation auto-expires
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_confirmation_deadline TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.payment_confirmation_deadline IS
  'Gateway-free GCash: deadline for the seller to confirm or reject the customer''s proof of payment. Set at order creation (now() + 30 min); extended to +2 hours when proof is submitted. The expiry sweep releases reserved stock and cancels the order after this.' ;

-- ────────────────────────────────────────────────────────────────
-- 3. One-open-order guard — atomic, race-proof abuse control
--    A customer may hold at most ONE awaiting-payment-confirmation
--    order (they can''t reserve stock across many dead checkouts).
--    The create RPC''s insert hits this index → 23505 → friendly error.
-- ────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_one_awaiting_payment_confirmation_per_customer
  ON public.orders(customer_id)
  WHERE status = 'awaiting_payment_confirmation';

COMMENT ON INDEX public.uq_orders_one_awaiting_payment_confirmation_per_customer IS
  'Abuse guard: one open awaiting-payment-confirmation order per customer. Frees automatically when the order is confirmed, rejected, or expired (status leaves awaiting_payment_confirmation).';

-- ────────────────────────────────────────────────────────────────
-- 4. gcash_payment_proofs — the customer''s submitted proof of payment
--    reference_number: normalized digits-only GCash ref (13 digits
--    standard, 12 tolerated — matches lib/utils/gcash_ref_extractor).
--    UNIQUE platform-wide → the same real payment can never confirm a
--    second order (screenshot reuse / fabricated-submission guard).
--    screenshot_url: REQUIRED (product decision), object path in the
--    PRIVATE 'payment-proofs' bucket (created in §7).
--    One proof per order (UNIQUE order_id) → a customer can''t stack
--    proofs; re-submission means a fresh checkout (new order).
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gcash_payment_proofs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL UNIQUE
                     REFERENCES public.orders(id) ON DELETE CASCADE,
  reference_number TEXT NOT NULL,
  screenshot_url   TEXT NOT NULL,
  submitted_by     UUID NOT NULL
                     REFERENCES public.profiles(id) ON DELETE RESTRICT,
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_gcash_payment_proofs_reference_number
    UNIQUE (reference_number),
  CONSTRAINT chk_gcash_payment_proofs_ref_format
    CHECK (reference_number ~ '^[0-9]{12,13}$')
);

CREATE INDEX IF NOT EXISTS idx_gcash_payment_proofs_order
  ON public.gcash_payment_proofs(order_id);

CREATE INDEX IF NOT EXISTS idx_gcash_payment_proofs_submitted
  ON public.gcash_payment_proofs(submitted_at DESC);

COMMENT ON TABLE public.gcash_payment_proofs IS
  'Proof of payment submitted by the customer for a gateway-free GCash order. reference_number is normalized digits-only and UNIQUE platform-wide. Written ONLY by the submit RPC (SECURITY DEFINER) — no client write policies.';

ALTER TABLE public.gcash_payment_proofs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can read own proof submissions" ON public.gcash_payment_proofs;
CREATE POLICY "Customers can read own proof submissions"
  ON public.gcash_payment_proofs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = gcash_payment_proofs.order_id
        AND o.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sellers can read proofs for their store's orders" ON public.gcash_payment_proofs;
CREATE POLICY "Sellers can read proofs for their store's orders"
  ON public.gcash_payment_proofs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.stores s ON s.id = o.store_id
      WHERE o.id = gcash_payment_proofs.order_id
        AND s.owner_id = auth.uid()
    )
  );

-- Intentionally NO INSERT / UPDATE / DELETE policies: proof rows are
-- append-only, written solely by the submit RPC.

-- ────────────────────────────────────────────────────────────────
-- 5. order_payment_events — append-only audit log for the payment
--    lifecycle (dispute reconstruction: actor + timestamp + notes).
--    The existing order_status_history trigger still logs status
--    transitions; this table adds payment-specific detail (who did
--    what, and the seller''s rejection reason).
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_payment_events (
  id         BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  order_id   UUID NOT NULL
               REFERENCES public.orders(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL
               CHECK (event_type IN
                 ('created', 'proof_submitted', 'confirmed',
                  'rejected', 'expired')),
  actor_id   UUID REFERENCES public.profiles(id),   -- NULL = system (expiry sweep)
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_payment_events_order
  ON public.order_payment_events(order_id, created_at ASC);

COMMENT ON TABLE public.order_payment_events IS
  'Append-only payment lifecycle log. event_type: created / proof_submitted / confirmed / rejected / expired. actor_id = the user who acted (NULL for the automated expiry sweep). Written only by SECURITY DEFINER RPCs.';

ALTER TABLE public.order_payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can read own payment events" ON public.order_payment_events;
CREATE POLICY "Customers can read own payment events"
  ON public.order_payment_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_payment_events.order_id
        AND o.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sellers can read payment events for their store's orders" ON public.order_payment_events;
CREATE POLICY "Sellers can read payment events for their store's orders"
  ON public.order_payment_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.stores s ON s.id = o.store_id
      WHERE o.id = order_payment_events.order_id
        AND s.owner_id = auth.uid()
    )
  );

-- Intentionally NO INSERT policies (append-only, RPC-written).

-- ────────────────────────────────────────────────────────────────
-- 6. TIGHTEN orders UPDATE policy — close the cross-store hole
--    Before: "Sellers and Admins can update order status" let ANY
--    seller role update ANY order row (whole-row, no store scoping) —
--    e.g. a seller could flip another store''s payment_status='paid'
--    straight from the client.
--    After: sellers may only update orders belonging to their OWN
--    store(s); admins keep full access. Every existing seller flow
--    (dashboard, manage orders, order detail, POS) operates on the
--    seller''s own store''s orders, so this regresses nothing.
--    The new payment transitions do NOT rely on this policy at all —
--    they go through SECURITY DEFINER RPCs with explicit
--    stores.owner_id checks. This policy exists for the legacy
--    seller status-update path only.
-- ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Sellers and Admins can update order status" ON public.orders;

CREATE POLICY "Sellers can update their own store's orders"
  ON public.orders FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE id = orders.store_id AND owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ────────────────────────────────────────────────────────────────
-- 7. Private storage bucket for proof screenshots
--    Screenshots may show personal/financial info (account name,
--    phone number) → PRIVATE bucket (public=false), readable only via
--    the policies below (and displayed with signed URLs).
--    Upload path convention: {order_id}/{uuid}.jpg — the FIRST folder
--    segment is the order id, so policies can join to orders/stores.
-- ────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-proofs', 'payment-proofs', false)
ON CONFLICT (id) DO NOTHING;

-- INSERT — the order's customer uploads into their own order's folder.
DROP POLICY IF EXISTS "Customers can upload payment proofs to their own order" ON storage.objects;
CREATE POLICY "Customers can upload payment proofs to their own order"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

-- SELECT — the order's customer OR the seller of the order's store.
DROP POLICY IF EXISTS "Order customers and sellers can read payment proofs" ON storage.objects;
CREATE POLICY "Order customers and sellers can read payment proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'payment-proofs'
    AND (
      (storage.foldername(name))[1] IN (
        SELECT o.id::text FROM public.orders o
        WHERE o.customer_id = auth.uid()
      )
      OR (storage.foldername(name))[1] IN (
        SELECT o.id::text FROM public.orders o
        JOIN public.stores s ON s.id = o.store_id
        WHERE s.owner_id = auth.uid()
      )
    )
  );

-- UPDATE / DELETE — the order's customer may replace/remove a bad
-- screenshot BEFORE submission. After submission the proof row is
-- locked (no update policy on gcash_payment_proofs); deleting the
-- object does not delete the proof row.
DROP POLICY IF EXISTS "Customers can replace their own payment proof images" ON storage.objects;
CREATE POLICY "Customers can replace their own payment proof images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Customers can delete their own payment proof images" ON storage.objects;
CREATE POLICY "Customers can delete their own payment proof images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT o.id::text FROM public.orders o
      WHERE o.customer_id = auth.uid()
    )
  );

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conrelid = 'public.orders'::regclass AND contype = 'c';
--
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'orders'
--   AND column_name IN ('payment_confirmation_deadline');
--
-- SELECT tablename FROM pg_tables
--   WHERE schemaname = 'public'
--   AND tablename IN ('gcash_payment_proofs', 'order_payment_events');
--
-- SELECT id, name, public FROM storage.buckets WHERE id = 'payment-proofs';
--
-- SELECT polname FROM pg_policy
--   WHERE polrelid = 'storage.objects'::regclass
--   AND polname LIKE '%payment proof%';
