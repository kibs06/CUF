-- ════════════════════════════════════════════════════════════════════
-- Bulk Reservation Deposits — step 2: columns, proofs table, RPCs
-- ════════════════════════════════════════════════════════════════════
-- Inserts a DEPOSIT GATE between seller approval and the stock draw:
--
--   pending → awaiting_deposit → reserved('approved') → fulfilled
--                │                        │
--                ▼                        ▼
--             expired                 cancelled
--        (24h passed unpaid,      (before: nothing to refund;
--         NO stock ever drawn)     after: deposit FORFEITED,
--                                  stock released)
--
-- Key change: approval no longer draws stock. It computes a deposit
-- (20% of the estimated value, rounded UP to a whole peso, stored as a
-- resolved amount so later price changes never change what's owed) and
-- starts a 24-hour deposit window. Real inventory leaves `inventory.stock`
-- ONLY when the store owner confirms the customer's GCash deposit proof —
-- mirroring the proof-verified direct-GCash pattern of
-- 20260808210000_add_direct_gcash_rpcs.sql (submit → seller confirm),
-- NOT a customer-trusted "pay" action.
--
-- Deviation from the original task brief (documented, user-approved):
-- the brief's `deposit_gcash_intent_id` column assumed the PayMongo
-- intent flow; the approved design reuses the direct-GCash PROOF pattern
-- instead, so the link column is `deposit_proof_id` →
-- `bulk_reservation_deposits.id` (this migration). The
-- `payment_intents` table has no order-free row type to reference.
--
-- Lifecycle mapping (enum values): the hold state keeps the existing
-- 'approved' enum value (renamed conceptually to "reserved" in the UI);
-- the new 'awaiting_deposit' value was added by
-- 20260913130000_add_bulk_reservation_awaiting_deposit_status.sql.
--
-- The seller's days-picker value ("hold for 1/3/7/… days") is stored at
-- approval in `expires_at` exactly as before — it simply becomes
-- OPERATIVE only once the deposit is confirmed. The deposit deadline is
-- separate (`deposit_deadline`, 24h). Edge: a 1-day hold paid at hour 23
-- leaves ~1 hour of hold — the seller chose the window, the customer
-- chose when to pay.
--
-- No new UPDATE policy on bulk_reservations — every state change still
-- goes through the SECURITY DEFINER RPCs below (same rule as §3 of
-- docs/AI/BULK_RESERVATION_ARCHITECTURE.md). The proofs table likewise
-- has NO write policies: submissions happen only via
-- submit_bulk_reservation_deposit_proof.
--
-- Depends on: 20260913120000_add_bulk_reservations.sql (table + RPCs)
--         and 20260913130000_…_awaiting_deposit_status.sql (enum value).
-- Idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. DEPOSIT COLUMNS on bulk_reservations
--    deposit_status is check-constrained TEXT (repo idiom for small
--    vocabularies; avoids ALTER TYPE churn): the brief's vocabulary is
--    kept exactly — not_required / unpaid / paid / forfeited / refunded.
--    'refunded' is reserved for a future seller-initiated refund flow
--    (no RPC sets it in this migration; forfeiture rules per the brief).
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.bulk_reservations
    ADD COLUMN IF NOT EXISTS deposit_amount   NUMERIC CHECK (deposit_amount > 0),
    ADD COLUMN IF NOT EXISTS deposit_status   TEXT NOT NULL DEFAULT 'not_required',
    ADD COLUMN IF NOT EXISTS deposit_deadline TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deposit_paid_at  TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_reservations_deposit_status'
    ) THEN
        ALTER TABLE public.bulk_reservations
            ADD CONSTRAINT chk_bulk_reservations_deposit_status
            CHECK (deposit_status IN
                ('not_required', 'unpaid', 'paid', 'forfeited', 'refunded'));
    END IF;
END
$$;

COMMENT ON COLUMN public.bulk_reservations.deposit_amount IS
    'Resolved deposit owed: ceil(20% of estimated value = product price × quantity at approval). Stored, not recomputed — later price changes never change what is owed.';
COMMENT ON COLUMN public.bulk_reservations.deposit_status IS
    'not_required (pre-approval/terminal-no-gate) / unpaid (awaiting 24h window) / paid (proof confirmed, stock drawn) / forfeited (cancelled or expired after paying — non-refundable per policy) / refunded (reserved for a future seller refund flow).';
COMMENT ON COLUMN public.bulk_reservations.deposit_deadline IS
    '24 hours from approval; passing it expires the reservation with NO stock drawn.';
COMMENT ON COLUMN public.bulk_reservations.deposit_paid_at IS
    'When the seller confirmed the deposit proof (== reserved_at).';

-- ────────────────────────────────────────────────────────────────
-- 2. PROOFS TABLE — mirrors gcash_payment_proofs conventions
--    (20260808200000): one proof per reservation, platform-wide UNIQUE
--    12–13 digit reference, REQUIRED screenshot path in the private
--    'payment-proofs' bucket, submitted_by audit. FK points at the
--    reservation instead of an order.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bulk_reservation_deposits (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id  UUID NOT NULL REFERENCES public.bulk_reservations(id) ON DELETE CASCADE,
    reference_number TEXT NOT NULL,
    -- PRIVATE bucket path: '{reservation_id}/{uuid}.jpg' — the FIRST
    -- folder segment is the reservation id so storage policies can
    -- authorize on it (same trick as the order proofs).
    screenshot_url  TEXT NOT NULL,
    submitted_by    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- One proof per reservation (a second submit → unique_violation → the
-- RPC re-raises a friendly code, mirroring submit_gcash_proof).
CREATE UNIQUE INDEX IF NOT EXISTS uq_bulk_reservation_deposits_reservation
    ON public.bulk_reservation_deposits (reservation_id);

-- Platform-wide unique reference: a single real GCash payment can never
-- confirm two deposits. Cross-table reuse (a reference already used for
-- an ORDER proof) is checked inside the submit RPC — a plain index
-- cannot span two tables.
CREATE UNIQUE INDEX IF NOT EXISTS uq_bulk_reservation_deposits_reference_number
    ON public.bulk_reservation_deposits (reference_number);

-- Same digit format as the order proofs (12, 13 tolerated).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_reservation_deposits_ref_format'
    ) THEN
        ALTER TABLE public.bulk_reservation_deposits
            ADD CONSTRAINT chk_bulk_reservation_deposits_ref_format
            CHECK (reference_number ~ '^[0-9]{12,13}$');
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_bulk_reservation_deposits_submitted
    ON public.bulk_reservation_deposits (submitted_at DESC);

COMMENT ON TABLE public.bulk_reservation_deposits IS
    'GCash deposit proofs for bulk reservations (direct-GCash pattern): customer submits reference + screenshot, store owner verifies in their GCash app and confirms — only the confirm draws stock. No UPDATE/DELETE policies: append-only via RPC.';

ALTER TABLE public.bulk_reservations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.bulk_reservation_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Customers can view their own deposit proofs"
    ON public.bulk_reservation_deposits FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.bulk_reservations
            WHERE id = reservation_id AND customer_id = auth.uid()
        )
    );

CREATE POLICY "Sellers can view deposit proofs for their store"
    ON public.bulk_reservation_deposits FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.bulk_reservations br
            JOIN public.stores s ON s.id = br.store_id
            WHERE br.id = reservation_id AND s.owner_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all deposit proofs"
    ON public.bulk_reservation_deposits FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- No INSERT/UPDATE/DELETE policies — submissions go through the SECURITY
-- DEFINER RPC below, exactly like gcash_payment_proofs.

-- Link column: which proof was accepted (set at seller confirm).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'bulk_reservations'
          AND column_name = 'deposit_proof_id'
    ) THEN
        ALTER TABLE public.bulk_reservations
            ADD COLUMN deposit_proof_id UUID
                REFERENCES public.bulk_reservation_deposits(id) ON DELETE SET NULL;
    END IF;
END
$$;

COMMENT ON COLUMN public.bulk_reservations.deposit_proof_id IS
    'The accepted proof row (set at seller confirm). The brief''s deposit_gcash_intent_id assumed the PayMongo intent flow; the approved design links the direct-GCash proof instead.';

-- ────────────────────────────────────────────────────────────────
-- 3. STORAGE — the private 'payment-proofs' bucket already exists
--    (20260808200000) with folder-based policies keyed to ORDER ids.
--    Deposit proofs live under '{reservation_id}/…', which those
--    policies do NOT cover — add the parallel reservation-join policies
--    using the exact same idiom.
-- ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Customers can upload bulk deposit proofs to their own reservation" ON storage.objects;
CREATE POLICY "Customers can upload bulk deposit proofs to their own reservation"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT br.id::text FROM public.bulk_reservations br
      WHERE br.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Bulk reservation customers and store sellers can read deposit proofs" ON storage.objects;
CREATE POLICY "Bulk reservation customers and store sellers can read deposit proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'payment-proofs'
    AND (
      (storage.foldername(name))[1] IN (
        SELECT br.id::text FROM public.bulk_reservations br
        WHERE br.customer_id = auth.uid()
      )
      OR (storage.foldername(name))[1] IN (
        SELECT br.id::text FROM public.bulk_reservations br
        JOIN public.stores s ON s.id = br.store_id
        WHERE s.owner_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "Customers can replace their own bulk deposit proof images" ON storage.objects;
CREATE POLICY "Customers can replace their own bulk deposit proof images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT br.id::text FROM public.bulk_reservations br
      WHERE br.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Customers can delete their own bulk deposit proof images" ON storage.objects;
CREATE POLICY "Customers can delete their own bulk deposit proof images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'payment-proofs'
    AND (storage.foldername(name))[1] IN (
      SELECT br.id::text FROM public.bulk_reservations br
      WHERE br.customer_id = auth.uid()
    )
  );

-- ────────────────────────────────────────────────────────────────
-- 4. RPC: REQUEST — one live request per customer per product now
--    includes 'awaiting_deposit' (an unpaid deposit window is still a
--    live hold on the seller's attention; prevents stacking a second
--    request while the first is pending payment).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_bulk_reservation(
    p_product_id UUID,
    p_store_id UUID,
    p_quantity INTEGER,
    p_requested_sizes JSONB DEFAULT '[]'::jsonb,
    p_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer UUID := auth.uid();
    v_available INTEGER;
    v_id UUID;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;
    IF p_quantity IS NULL OR p_quantity < 1 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.products
        WHERE id = p_product_id
          AND store_id = p_store_id
          AND is_active = true
    ) THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;

    SELECT COALESCE(SUM(stock), 0) INTO v_available
    FROM public.inventory WHERE product_id = p_product_id;
    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'INSUFFICIENT_STOCK (%) < %', v_available, p_quantity;
    END IF;

    -- One live request per customer per product at a time. Deposit-gate
    -- update: 'awaiting_deposit' is live too (deposit not yet confirmed).
    IF EXISTS (
        SELECT 1 FROM public.bulk_reservations
        WHERE customer_id = v_customer
          AND product_id = p_product_id
          AND status IN ('pending', 'awaiting_deposit', 'approved')
    ) THEN
        RAISE EXCEPTION 'RESERVATION_ALREADY_EXISTS';
    END IF;

    INSERT INTO public.bulk_reservations (
        customer_id, store_id, product_id, quantity,
        requested_sizes, note, status
    ) VALUES (
        v_customer, p_store_id, p_product_id, p_quantity,
        p_requested_sizes, p_note, 'pending'
    ) RETURNING id INTO v_id;

    INSERT INTO public.notifications (user_id, category, title, message)
    SELECT s.owner_id, 'reservations',
           'New bulk reservation request',
           'A customer requested ' || p_quantity || ' units of ' ||
           COALESCE(p.name, 'a product') || ' for resale.'
    FROM public.stores s
    JOIN public.products p ON p.id = p_product_id
    WHERE s.id = p_store_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_bulk_reservation TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 5. RPC: DECIDE (seller) — approve now STARTS THE DEPOSIT WINDOW and
--    does NOT draw stock. The stock draw moved verbatim into
--    confirm_bulk_reservation_deposit (§6) — byte-for-byte the same
--    loop, new home.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decide_bulk_reservation(
    p_reservation_id UUID,
    p_approve BOOLEAN,
    p_days INTEGER DEFAULT NULL,        -- required when approving
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_seller UUID := auth.uid();
    v_price NUMERIC;
    v_deposit NUMERIC;
    v_deadline TIMESTAMPTZ;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize concurrent decisions

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;

    IF v_reservation.status <> 'pending' THEN
        RAISE EXCEPTION 'ALREADY_DECIDED';
    END IF;

    IF NOT p_approve THEN
        UPDATE public.bulk_reservations
        SET status = 'rejected',
            rejection_reason = p_rejection_reason
        WHERE id = p_reservation_id;

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_reservation.customer_id, 'reservations',
            'Bulk reservation declined',
            'The seller declined your reservation request' ||
            CASE WHEN p_rejection_reason IS NOT NULL AND p_rejection_reason <> ''
                 THEN ': ' || p_rejection_reason ELSE '.' END
        );
        RETURN;
    END IF;

    -- ── APPROVE: open the deposit window (NO stock moves yet) ──────
    IF p_days IS NULL OR p_days < 1 THEN
        RAISE EXCEPTION 'INVALID_DEADLINE';
    END IF;

    -- Deposit = 20% of the estimated value (quantity × product price at
    -- approval), rounded UP to a whole peso. Stored resolved — §2 rule.
    -- The ORIGINAL `price` is used, not the sale price: a reseller hold
    -- is priced at pickup, and the sale could expire before the deposit
    -- is even paid. Pinning to the base price keeps deposit ≠ sale-price
    -- arbitrage out of the flow.
    SELECT price INTO v_price
    FROM public.products WHERE id = v_reservation.product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
    END IF;
    v_deposit := ceil(v_price * v_reservation.quantity * 0.20);

    -- Deposit window: 24 hours from approval (§2 default).
    v_deadline := timezone('utc'::text, now()) + interval '24 hours';

    UPDATE public.bulk_reservations
    SET status = 'awaiting_deposit',
        deposit_amount = v_deposit,
        deposit_status = 'unpaid',
        deposit_deadline = v_deadline,
        -- Seller's chosen hold window, stored exactly as the old flow
        -- did; it becomes operative only when the deposit is confirmed.
        expires_at = timezone('utc'::text, now()) + make_interval(days => p_days)
    WHERE id = p_reservation_id;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation approved — deposit required',
        'Your reservation of ' || v_reservation.quantity || ' units was ' ||
        'approved. Pay the ₱' || v_deposit::int ||
        ' GCash deposit (20% of the estimated value) by ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') ||
        ' UTC to hold the stock. The deposit is NON-REFUNDABLE once paid.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.decide_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_bulk_reservation TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 6. RPC: SUBMIT DEPOSIT PROOF (customer) — mirrors submit_gcash_proof:
--    ownership + state + deadline + reference format + screenshot-folder
--    validation, one-proof-per-reservation unique, platform-wide
--    reference dedupe (deposit table unique index + explicit check
--    against order proofs). Does NOT touch stock and does NOT flip
--    status — only the seller's confirm does.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_bulk_reservation_deposit_proof(
    p_reservation_id   UUID,
    p_reference_number TEXT,
    p_screenshot_url   TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_customer UUID := auth.uid();
    v_store_owner UUID;
    v_ref TEXT;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize vs confirm/reject/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'awaiting_deposit' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;
    IF v_reservation.deposit_deadline IS NOT NULL
       AND v_reservation.deposit_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'DEPOSIT_DEADLINE_PASSED';
    END IF;
    IF p_screenshot_url IS NULL OR p_screenshot_url = '' THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;
    -- The screenshot must live in THIS reservation's folder
    -- ({reservation_id}/{file}) — same anti-mixing rule as order proofs.
    IF split_part(p_screenshot_url, '/', 1) <> p_reservation_id::text THEN
        RAISE EXCEPTION 'INVALID_PROOF_SCREENSHOT';
    END IF;

    -- Normalize to digits-only; GCash refs are 13 digits (12 tolerated —
    -- matches lib/utils/gcash_ref_extractor and the order-flow rule).
    v_ref := regexp_replace(COALESCE(p_reference_number, ''), '\D', '', 'g');
    IF length(v_ref) NOT IN (12, 13) THEN
        RAISE EXCEPTION 'INVALID_PROOF_REFERENCE';
    END IF;

    -- Platform-wide dedupe ACROSS proof families: a reference already
    -- used for an order proof cannot confirm a deposit too. (The reverse
    -- direction — the dormant order flow checking deposits — is not
    -- added; the order flow is legacy and out of scope here.) Guarded on
    -- to_regclass so the migration is safe even where the dormant
    -- order-proof table was never created.
    IF to_regclass('public.gcash_payment_proofs') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.gcash_payment_proofs
                   WHERE reference_number = v_ref) THEN
            RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.bulk_reservation_deposits
            (reservation_id, reference_number, screenshot_url, submitted_by)
        VALUES (p_reservation_id, v_ref, p_screenshot_url, v_customer);
    EXCEPTION WHEN unique_violation THEN
        -- Distinguish the concurrent double-submit race (reservation_id
        -- UNIQUE) from a genuinely reused reference (platform UNIQUE).
        IF EXISTS (SELECT 1 FROM public.bulk_reservation_deposits
                   WHERE reservation_id = p_reservation_id) THEN
            RAISE EXCEPTION 'DEPOSIT_ALREADY_SUBMITTED';
        END IF;
        RAISE EXCEPTION 'REFERENCE_ALREADY_USED';
    END;

    -- Notify the seller that a proof awaits verification.
    SELECT s.owner_id INTO v_store_owner
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    IF v_store_owner IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_store_owner, 'reservations',
            'Deposit proof submitted',
            'A customer submitted a GCash deposit proof (₱' ||
            COALESCE(v_reservation.deposit_amount, 0)::int || ', ref ' ||
            v_ref || ') for their ' || v_reservation.quantity ||
            '-unit reservation. Verify it in your GCash app and confirm to hold the stock.'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_bulk_reservation_deposit_proof FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_bulk_reservation_deposit_proof TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 7. RPC: CONFIRM DEPOSIT (seller) — the security control. This is
--    where the stock draw happens now: the exact loop relocated from
--    the old decide_bulk_reservation approve-branch (largest stock
--    first, FOR UPDATE row locks, abort loudly if stock shrank), NOT a
--    rewrite. Deadline is re-checked here: a proof submitted at minute
--    23 is still confirmed past the hour — the seller verifying real
--    money in their own GCash app is the stronger signal (same
--    deadline decision as confirm_gcash_payment).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_bulk_reservation_deposit(
    p_reservation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_seller UUID := auth.uid();
    v_remaining INTEGER;
    v_taken INTEGER;
    v_size_row RECORD;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize vs submit/reject/sweep
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'awaiting_deposit' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;
    IF v_reservation.deposit_deadline IS NOT NULL
       AND v_reservation.deposit_deadline <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'DEPOSIT_DEADLINE_PASSED';
    END IF;

    -- The customer must have submitted proof before the seller confirms.
    IF NOT EXISTS (
        SELECT 1 FROM public.bulk_reservation_deposits
        WHERE reservation_id = p_reservation_id
    ) THEN
        RAISE EXCEPTION 'DEPOSIT_PROOF_REQUIRED';
    END IF;

    -- ── Draw stock — relocated verbatim from decide_bulk_reservation ──
    v_remaining := v_reservation.quantity;

    -- Draw stock per size, largest sizes first, never below 0
    -- (inventory has a stock >= 0 CHECK that guards the last unit).
    FOR v_size_row IN (
        SELECT size, stock FROM public.inventory
        WHERE product_id = v_reservation.product_id AND stock > 0
        ORDER BY stock DESC
        FOR UPDATE
    ) LOOP
        EXIT WHEN v_remaining <= 0;
        v_taken := LEAST(v_size_row.stock, v_remaining);
        UPDATE public.inventory
        SET stock = stock - v_taken,
            updated_at = timezone('utc'::text, now())
        WHERE product_id = v_reservation.product_id
          AND size = v_size_row.size;
        v_remaining := v_remaining - v_taken;
    END LOOP;

    IF v_remaining > 0 THEN
        -- Stock moved between approval and payment (someone else bought
        -- it via another path) — abort loudly; the reservation stays
        -- awaiting_deposit so the seller can decline or restock.
        RAISE EXCEPTION 'INSUFFICIENT_STOCK_MISSING_%', v_remaining;
    END IF;

    UPDATE public.bulk_reservations
    SET status = 'approved',               -- "reserved" in the UI
        reserved_stock = v_reservation.quantity,
        reserved_at = timezone('utc'::text, now()),
        deposit_status = 'paid',
        deposit_paid_at = timezone('utc'::text, now()),
        deposit_proof_id = (
            SELECT id FROM public.bulk_reservation_deposits
            WHERE reservation_id = p_reservation_id
            LIMIT 1
        )
    WHERE id = p_reservation_id;

    -- NOTE (deliberately deferred): recording the deposit as applied
    -- toward an eventual sale (convert-to-POS-sale RPC) is out of scope
    -- for this migration — see §6 "Deliberate non-goals" of
    -- docs/AI/BULK_RESERVATION_ARCHITECTURE.md. The data model already
    -- supports it: deposit_amount (resolved) + deposit_paid_at +
    -- deposit_proof_id + status='fulfilled' survive without reshaping.

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Deposit received — stock reserved',
        'Your ₱' || COALESCE(v_reservation.deposit_amount, 0)::int ||
        ' deposit was confirmed. Your ' || v_reservation.quantity ||
        ' units are now reserved' ||
        CASE WHEN v_reservation.expires_at IS NOT NULL
             THEN ' until ' || to_char(v_reservation.expires_at AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') || ' UTC'
             ELSE '' END ||
        '. Remember: the deposit is non-refundable.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_bulk_reservation_deposit FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_bulk_reservation_deposit TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 8. RPC: REJECT DEPOSIT (seller) — mirrors reject_gcash_payment.
--    Terminal 'rejected'; no stock was ever drawn; deposit stays
--    'unpaid' (never verified as paid). Use when the proof is invalid
--    or the window lapsed with money un-verifiable.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_bulk_reservation_deposit(
    p_reservation_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_seller UUID := auth.uid();
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'awaiting_deposit' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    UPDATE public.bulk_reservations
    SET status = 'rejected',
        rejection_reason = COALESCE(NULLIF(p_reason, ''),
            'Deposit payment could not be verified'),
        deposit_status = 'not_required'
    WHERE id = p_reservation_id;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Deposit payment declined',
        'The seller could not verify your deposit payment for the ' ||
        v_reservation.quantity || '-unit reservation' ||
        CASE WHEN p_reason IS NOT NULL AND p_reason <> ''
             THEN ': ' || p_reason ELSE '.' END ||
        ' No stock was held. If you already sent money, contact the store directly to resolve it.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.reject_bulk_reservation_deposit FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_bulk_reservation_deposit TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 9. PRIVATE HELPER: _release_bulk_reservation_stock gains an explicit
--    deposit-status outcome, because "release" now has two different
--    reasons that must not be conflated:
--      • expired/cancelled hold that WAS paid  → 'forfeited' (§2 policy)
--      • release with nothing paid / no gate   → NULL (leave as-is:
--        'not_required' pre-approval, 'unpaid' when the window closed
--        unpaid or the customer cancelled before paying)
--    Callers pass NULL when the deposit state is already final.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._release_bulk_reservation_stock(
    p_reservation_id UUID,
    p_expected_status bulk_reservation_status,
    p_new_status bulk_reservation_status,
    p_deposit_status TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_reservation public.bulk_reservations%ROWTYPE;
    v_remaining INTEGER;
    v_size_row RECORD;
BEGIN
    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;                          -- serialize against decide/fulfill

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.status <> p_expected_status THEN
        RETURN;                          -- already released; idempotent no-op
    END IF;
    IF v_reservation.reserved_stock <= 0 THEN
        -- Holds with nothing drawn (pending / awaiting_deposit); still
        -- safe to flip status.
        UPDATE public.bulk_reservations
        SET status = p_new_status,
            deposit_status = COALESCE(p_deposit_status, deposit_status),
            released_at = CASE
                WHEN p_new_status IN ('cancelled', 'expired') THEN timezone('utc'::text, now())
                ELSE released_at END,
            fulfilled_at = CASE
                WHEN p_new_status = 'fulfilled' THEN timezone('utc'::text, now())
                ELSE fulfilled_at END
        WHERE id = p_reservation_id;
        RETURN;
    END IF;

    -- Return units to the sizes with the LOWEST stock first (closest to
    -- the original draw; keeps size distribution balanced). If a size
    -- row was deleted meanwhile, fall back to any row for the product.
    v_remaining := v_reservation.reserved_stock;
    FOR v_size_row IN (
        SELECT size FROM public.inventory
        WHERE product_id = v_reservation.product_id
        ORDER BY stock ASC
        FOR UPDATE
    ) LOOP
        EXIT WHEN v_remaining <= 0;
        UPDATE public.inventory
        SET stock = stock + 1,
            updated_at = timezone('utc'::text, now())
        WHERE product_id = v_reservation.product_id
          AND size = v_size_row.size;
        v_remaining := v_remaining - 1;
    END LOOP;

    -- Inventory row(s) deleted while held: recreate a restock row so the
    -- units are never lost (mirrors the GCash RPC edge-case handling).
    IF v_remaining > 0 THEN
        INSERT INTO public.inventory (product_id, size, stock)
        VALUES (v_reservation.product_id, 'Restock', v_remaining)
        ON CONFLICT (product_id, size)
        DO UPDATE SET stock = public.inventory.stock + EXCLUDED.stock,
                      updated_at = timezone('utc'::text, now());
    END IF;

    UPDATE public.bulk_reservations
    SET status = p_new_status,
        deposit_status = COALESCE(p_deposit_status, deposit_status),
        released_at = CASE
            WHEN p_new_status IN ('cancelled', 'expired') THEN timezone('utc'::text, now())
            ELSE released_at END,
        fulfilled_at = CASE
            WHEN p_new_status = 'fulfilled' THEN timezone('utc'::text, now())
            ELSE fulfilled_at END
    WHERE id = p_reservation_id;
END;
$$;

-- ────────────────────────────────────────────────────────────────
-- 10. RPC: CANCEL (customer) — extended for the deposit gate:
--       • pending           → cancelled, deposit untouched (not_required)
--       • awaiting_deposit  → cancelled, NOTHING drawn, deposit stays
--         'unpaid' (nothing to refund — nothing was ever verified paid)
--       • approved (paid)   → cancelled, stock released,
--         deposit_status = 'forfeited' (non-refundable per §2 policy)
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_bulk_reservation(p_reservation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_customer UUID := auth.uid();
    v_store_owner UUID;
    v_reservation public.bulk_reservations%ROWTYPE;
    v_deposit_outcome TEXT;
BEGIN
    IF v_customer IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF v_reservation.customer_id <> v_customer THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status NOT IN ('pending', 'awaiting_deposit', 'approved') THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    -- §2 refund policy: paid hold → forfeiture; anything earlier → the
    -- deposit state simply stays as-is (never verified paid).
    v_deposit_outcome := CASE
        WHEN v_reservation.status = 'approved' THEN 'forfeited'
        ELSE NULL END;

    PERFORM public._release_bulk_reservation_stock(
        p_reservation_id, v_reservation.status, 'cancelled', v_deposit_outcome);

    -- Notify the seller.
    SELECT s.owner_id INTO v_store_owner
    FROM public.stores s WHERE s.id = v_reservation.store_id;
    IF v_store_owner IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_store_owner, 'reservations',
            'Bulk reservation cancelled',
            'The customer cancelled their reservation of ' ||
            v_reservation.quantity || ' units.' ||
            CASE WHEN v_reservation.status = 'approved'
                 THEN ' Their paid deposit (₱' ||
                      COALESCE(v_reservation.deposit_amount, 0)::int ||
                      ') is forfeited per the non-refundable policy; the stock is back in inventory.'
                 ELSE '' END
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_bulk_reservation TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 11. RPC: FULFILL (seller) — unchanged semantics: only a PAID hold
--     ('approved') can be fulfilled. Fulfilling an unpaid
--     awaiting_deposit reservation is intentionally NOT supported —
--     confirm the deposit first (it is one tap). The deposit stays
--     'paid' and is recorded as applied toward the (still-unbuilt)
--     eventual sale — see the deferred note in §7 above and §6 of the
--     architecture doc.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fulfill_bulk_reservation(p_reservation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seller UUID := auth.uid();
    v_reservation public.bulk_reservations%ROWTYPE;
BEGIN
    IF v_seller IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_reservation FROM public.bulk_reservations
    WHERE id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_reservation.store_id AND owner_id = v_seller
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN';
    END IF;
    IF v_reservation.status <> 'approved' THEN
        RAISE EXCEPTION 'ALREADY_RESOLVED';
    END IF;

    PERFORM public._release_bulk_reservation_stock(
        p_reservation_id, 'approved', 'fulfilled', NULL);

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation fulfilled',
        'Your reservation of ' || v_reservation.quantity ||
        ' units was completed. Your ₱' ||
        COALESCE(v_reservation.deposit_amount, 0)::int ||
        ' deposit is applied toward this purchase. Thank you for your business!'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fulfill_bulk_reservation FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fulfill_bulk_reservation TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 12. RPC: EXPIRY SWEEP — TWO SEPARATE BRANCHES, never merged (they
--     have different consequences: one releases stock, one doesn't):
--       a) awaiting_deposit AND deposit_deadline <= now()
--          → terminal expire, NO stock release (none was drawn),
--            deposit stays 'unpaid', customer notified the window closed.
--       b) approved AND expires_at <= now() (the original branch)
--          → release stock, deposit 'forfeited' (it was paid — §2).
--     Still no pg_cron on this database (see
--     20260907000000_fix_stale_pending_gcash_intents.sql): the Flutter
--     app calls this opportunistically on every reservations/queue load.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_bulk_reservations()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_row RECORD;
    v_count INTEGER := 0;
BEGIN
    -- Branch a: unpaid deposit windows that lapsed. Nothing was ever
    -- drawn — terminal flip only.
    FOR v_row IN (
        SELECT id, customer_id, quantity
        FROM public.bulk_reservations
        WHERE status = 'awaiting_deposit'
          AND deposit_deadline IS NOT NULL
          AND deposit_deadline <= timezone('utc'::text, now())
        FOR UPDATE SKIP LOCKED
    ) LOOP
        PERFORM public._release_bulk_reservation_stock(
            v_row.id, 'awaiting_deposit', 'expired', NULL);

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_row.customer_id, 'reservations',
            'Deposit window expired',
            'The 24-hour window to pay the deposit for your ' ||
            v_row.quantity || '-unit reservation closed — the request ' ||
            'expired and no stock was held. You can request again.'
        );
        v_count := v_count + 1;
    END LOOP;

    -- Branch b: paid holds past their pickup deadline (original branch,
    -- now with the forfeiture outcome per §2).
    FOR v_row IN (
        SELECT id, customer_id, quantity
        FROM public.bulk_reservations
        WHERE status = 'approved'
          AND expires_at IS NOT NULL
          AND expires_at <= timezone('utc'::text, now())
        FOR UPDATE SKIP LOCKED
    ) LOOP
        PERFORM public._release_bulk_reservation_stock(
            v_row.id, 'approved', 'expired', 'forfeited');

        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            v_row.customer_id, 'reservations',
            'Bulk reservation expired',
            'Your reservation of ' || v_row.quantity ||
            ' units expired — the items are back in the store''s stock. ' ||
            'Per the policy you accepted, the paid deposit is forfeited. You can request again.'
        );
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_bulk_reservations FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_bulk_reservations TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 13. reserved_stock_for_product — VERIFIED, NO CHANGE NEEDED.
--     It sums reserved_stock WHERE status = 'approved'. 'awaiting_deposit'
--     rows hold reserved_stock = 0 and have NOT drawn inventory, so
--     including them would be a no-op at best; the checkout-side
--     availability math stays correct because held units are gone from
--     inventory.stock only after the deposit confirm. Deliberately left
--     untouched (re-stated here so the review sees the reasoning).
-- ────────────────────────────────────────────────────────────────

-- Sweep index for branch a (mirrors the existing expires_at partial).
CREATE INDEX IF NOT EXISTS idx_bulk_reservations_deposit_expiry
    ON public.bulk_reservations (deposit_deadline) WHERE status = 'awaiting_deposit';

-- ════════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ════════════════════════════════════════════════════════════════════
-- SELECT unnest(enum_range(NULL::bulk_reservation_status));  -- expect 'awaiting_deposit' after 'pending'
--
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'bulk_reservations'
--     AND column_name LIKE 'deposit%';   -- expect 5 rows incl. deposit_proof_id
--
-- SELECT has_function_privilege('authenticated',
--   'public.submit_bulk_reservation_deposit_proof(uuid,text,text)', 'EXECUTE');  -- expect true
-- SELECT has_function_privilege('authenticated',
--   'public.confirm_bulk_reservation_deposit(uuid)', 'EXECUTE');                 -- expect true
-- SELECT has_function_privilege('anon',
--   'public.submit_bulk_reservation_deposit_proof(uuid,text,text)', 'EXECUTE');  -- expect false
--
-- SELECT polname FROM pg_policy
--   WHERE polrelid = 'storage.objects'::regclass
--     AND polname LIKE '%bulk deposit%';   -- expect 4 rows
--
-- -- No UPDATE policy crept onto bulk_reservations:
-- SELECT count(*) FROM pg_policy
--   WHERE polrelid = 'public.bulk_reservations'::regclass AND polcmd = 'UPDATE';  -- expect 0
