-- ═══════════════════════════════════════════════════════════════════════
-- 20261118080000_gcash_reference_single_use.sql
--
-- One GCash transfer must pay exactly once, anywhere in the product.
--
-- What already holds (checked before writing this file):
--   • gcash_payment_proofs.reference_number  is UNIQUE and digit-checked
--     (20260808200000) — the same reference cannot back two proofs.
--   • bulk_reservation_deposits.reference_number is UNIQUE and digit-checked
--     (20260913140000) — the same reference cannot back two deposits.
--   • orders.gcash_reference_number is UNIQUE only among PAID orders
--     (20260905000000, partial index) — the POS confirm path.
--
-- What did not hold: the three ledgers were never compared with each other.
-- So a customer could send ₱1,000 once and substantiate it twice —
--   order A's proof + reservation B's deposit,
--   order A's proof + a POS sale the seller rang up with that number,
--   a deposit  + a POS sale,
-- each of which is unique inside its own table and therefore passed every
-- check. That is duplication in the only sense that costs money.
--
-- This file adds one STABLE helper that answers "who already owns this
-- reference?" across all three, and a BEFORE trigger on each writer that
-- refuses the write when somebody else owns it:
--
--   gcash_payment_proofs      INSERT / UPDATE OF reference_number
--   orders                    INSERT / UPDATE OF gcash_reference_number
--   bulk_reservation_deposits INSERT / UPDATE OF reference_number
--
-- Deliberate properties:
--   • Same-owner rows are excluded (an order and its own proof are one
--     payment, not two; a deposit and its own reservation likewise), so the
--     legitimate pair is never rejected.
--   • Only 12–13 digit references are compared. PayMongo's legacy `pi_…`
--     ids live in orders.gcash_reference_number and mean something else;
--     normalising both sides to digits keeps them out of each other's way,
--     and lets a seller who types "4043 676 687260" still collide with the
--     stored "4043676687260".
--   • A refusal is a P0001 RAISE with a sentence a person can act on, which
--     the app already surfaces verbatim (DirectGcashService._toException).
--   • Nothing is repaired: existing cross-table duplicates, if any, are
--     reported by the query at the bottom of this file and left for a human
--     to refund or cancel. Deleting money evidence automatically is exactly
--     what a fix like this should not do.
--
-- Additive and idempotent: one function, one trigger function, three
-- triggers and one expression index. No backfill, no policy or grant change,
-- no column change.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Who already owns this reference? ────────────────────────────────
CREATE OR REPLACE FUNCTION public.gcash_reference_owner(
  p_ref            text,
  p_order_id       uuid DEFAULT NULL,
  p_reservation_id uuid DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner text;
BEGIN
  -- A paid or claimed order carrying the number in its own column. This is
  -- the POS path: the seller rang the sale up against that transfer.
  SELECT 'order ' || COALESCE(o.order_code, left(o.id::text, 8))
    INTO v_owner
    FROM public.orders o
   WHERE regexp_replace(COALESCE(o.gcash_reference_number, ''), '\D', '', 'g') = p_ref
     AND o.id IS DISTINCT FROM p_order_id
     AND (o.payment_status = 'paid' OR o.status = 'payment_under_review')
   LIMIT 1;
  IF v_owner IS NOT NULL THEN
    RETURN v_owner;
  END IF;

  -- A proof submitted for some other order (any status: a rejected attempt
  -- still names the transfer the customer says they made).
  SELECT 'order ' || COALESCE(o.order_code, left(o.id::text, 8))
    INTO v_owner
    FROM public.gcash_payment_proofs p
    JOIN public.orders o ON o.id = p.order_id
   WHERE p.reference_number = p_ref
     AND p.order_id IS DISTINCT FROM p_order_id
   LIMIT 1;
  IF v_owner IS NOT NULL THEN
    RETURN v_owner;
  END IF;

  -- A bulk-reservation deposit.
  SELECT 'reservation ' || left(d.reservation_id::text, 8)
    INTO v_owner
    FROM public.bulk_reservation_deposits d
   WHERE d.reference_number = p_ref
     AND d.reservation_id IS DISTINCT FROM p_reservation_id
   LIMIT 1;

  RETURN v_owner;
END;
$$;

COMMENT ON FUNCTION public.gcash_reference_owner(text, uuid, uuid) IS
  'Returns which order/reservation already owns a 12-13 digit GCash reference across proofs, paid-or-claimed orders and reservation deposits; NULL when the reference is free. Same-owner rows are excluded.';

-- ── 2. The guard every writer runs through ─────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_gcash_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row         jsonb := to_jsonb(NEW);
  v_raw         text;
  v_ref         text;
  v_order       uuid;
  v_reservation uuid;
  v_owner       text;
BEGIN
  v_raw := CASE TG_TABLE_NAME
             WHEN 'orders' THEN v_row ->> 'gcash_reference_number'
             ELSE v_row ->> 'reference_number'
           END;

  -- Digits only, so "4043 676 687260" and "4043676687260" are the same
  -- transfer. Anything that is not a 12-13 digit reference (a PayMongo
  -- pi_… id, an empty string, a mistyped short number) is not ours to judge.
  v_ref := regexp_replace(COALESCE(v_raw, ''), '\D', '', 'g');
  IF length(v_ref) NOT IN (12, 13) THEN
    RETURN NEW;
  END IF;

  v_order := CASE TG_TABLE_NAME
               WHEN 'orders' THEN (v_row ->> 'id')::uuid
               WHEN 'gcash_payment_proofs' THEN (v_row ->> 'order_id')::uuid
             END;
  v_reservation := CASE TG_TABLE_NAME
                     WHEN 'bulk_reservation_deposits' THEN (v_row ->> 'reservation_id')::uuid
                   END;

  v_owner := public.gcash_reference_owner(v_ref, v_order, v_reservation);
  IF v_owner IS NOT NULL THEN
    RAISE EXCEPTION
      'That GCash reference number is already used for % — one transfer can only pay once.',
      v_owner;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_gcash_reference() IS
  'BEFORE INSERT/UPDATE guard on gcash_payment_proofs, orders and bulk_reservation_deposits: refuses a 12-13 digit GCash reference already owned by a different payment.';

DROP TRIGGER IF EXISTS trg_guard_gcash_reference ON public.gcash_payment_proofs;
CREATE TRIGGER trg_guard_gcash_reference
  BEFORE INSERT OR UPDATE OF reference_number ON public.gcash_payment_proofs
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

DROP TRIGGER IF EXISTS trg_guard_gcash_reference_orders ON public.orders;
CREATE TRIGGER trg_guard_gcash_reference_orders
  BEFORE INSERT OR UPDATE OF gcash_reference_number ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

DROP TRIGGER IF EXISTS trg_guard_gcash_reference_deposits ON public.bulk_reservation_deposits;
CREATE TRIGGER trg_guard_gcash_reference_deposits
  BEFORE INSERT OR UPDATE OF reference_number ON public.bulk_reservation_deposits
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_gcash_reference();

-- ── 3. Index the normalised reference on orders ─────────────────────────
-- The guard compares DIGITS, not the raw text (a seller may type "4043 676
-- 687260"), so the existing column index cannot serve that comparison and the
-- lookup would be a sequential scan of orders on every proof submission, every
-- POS confirm and every order insert. `regexp_replace(text,text,text,text)` is
-- IMMUTABLE, so the expression can be indexed; the proofs and deposits ledgers
-- already have a plain unique index on the exact column.
CREATE INDEX IF NOT EXISTS idx_orders_gcash_reference_digits
  ON public.orders (
    (regexp_replace(COALESCE(gcash_reference_number, ''), '\D', '', 'g'))
  );

COMMENT ON INDEX public.idx_orders_gcash_reference_digits IS
  'Digits-only form of orders.gcash_reference_number. Serves gcash_reference_owner(), which compares normalised references so a spaced entry collides with a stored one.';

COMMIT;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 0. The lookup index is there (and is used — see EXPLAIN in §5):
-- SELECT indexdef FROM pg_indexes
--  WHERE tablename = 'orders' AND indexname = 'idx_orders_gcash_reference_digits';
--
-- 1. The three guards are armed:
-- SELECT c.relname, t.tgname
--   FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
--  WHERE NOT t.tgisinternal
--    AND t.tgname LIKE 'trg_guard_gcash_reference%'
--  ORDER BY 1;
--   -- bulk_reservation_deposits | gcash_payment_proofs | orders
--
-- 2. A reference nobody owns is free:
-- SELECT public.gcash_reference_owner('999999999999');   -- NULL
--
-- 3. The same numbers in different formats are one number:
-- SELECT regexp_replace('4043 676 687260', '\D', '', 'g');  -- 4043676687260
--
-- 4. Cross-table duplicates that already exist (nothing is changed by this
--    file — this is the list to work through by hand):
-- SELECT 'order vs proof' AS kind, o.order_code, p.reference_number
--   FROM public.orders o
--   JOIN public.gcash_payment_proofs p
--     ON p.reference_number = regexp_replace(COALESCE(o.gcash_reference_number,''), '\D','','g')
--  WHERE o.id <> p.order_id
-- UNION ALL
-- SELECT 'proof vs deposit', NULL, p.reference_number
--   FROM public.gcash_payment_proofs p
--   JOIN public.bulk_reservation_deposits d ON d.reference_number = p.reference_number
-- UNION ALL
-- SELECT 'order vs deposit', o.order_code, d.reference_number
--   FROM public.orders o
--   JOIN public.bulk_reservation_deposits d
--     ON d.reference_number = regexp_replace(COALESCE(o.gcash_reference_number,''), '\D','','g');
--   -- expect 0 rows; any row is a real double-payment to resolve
--
-- Rollback: DROP TRIGGER trg_guard_gcash_reference ON public.gcash_payment_proofs;
--           DROP TRIGGER trg_guard_gcash_reference_orders ON public.orders;
--           DROP TRIGGER trg_guard_gcash_reference_deposits ON public.bulk_reservation_deposits;
--           DROP FUNCTION public.guard_gcash_reference();
--           DROP FUNCTION public.gcash_reference_owner(text, uuid, uuid);
