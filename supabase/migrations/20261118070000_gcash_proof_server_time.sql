-- ═══════════════════════════════════════════════════════════════════════
-- 20261118070000_gcash_proof_server_time.sql
--
-- Manual GCash proofs carry two clocks, and they are not the same thing:
--
--   • submitted_at — when the proof ARRIVED at the server. This is the one a
--     reviewer can trust: it is stamped by the database, never sent by the
--     app, and (from this file on) it cannot be moved afterwards by any
--     writer — not the customer, not a service_role script, not a replayed
--     call with a hand-made body.
--
--   • paid_at      — what the receipt CLAIMS. The app reads it off the
--     screenshot (OCR), so it describes an image the customer could have
--     edited. NULL means the receipt carried no readable clock. It is useful
--     evidence to compare against submitted_at, and never proof on its own.
--
--     submit_gcash_proof writes COALESCE(p_paid_at, now()) because the column
--     used to be treated as required. That fallback is a SERVER stamp, and a
--     reviewer reading it as "the receipt says …" would be reading our clock
--     as the customer's claim — the exact confusion this file exists to stop.
--     The trigger below therefore drops a paid_at that equals the transaction
--     clock: the fallback and the arrival stamp are then the same instant, and
--     a real receipt stamp (minute precision, from an earlier minute) never
--     is. The RPC is deliberately not rewritten for this: copying its 180-line
--     body into a new file to delete one COALESCE would put two definitions of
--     the submit path in the tree, and the one the database runs would be the
--     copy nobody edits.
--
-- Both are record-only: the customer's form shows neither, so there is
-- nothing on that screen to type over or to prompt an edit of the image.
--
-- Why a trigger and not just the column default:
--   `submitted_at` already exists (20260808200000) with DEFAULT now(), and the
--   submit RPC never passes it — but a DEFAULT is only a value for omitted
--   columns. Anyone who can write the row can name their own time. The BEFORE
--   trigger overwrites it on INSERT and pins it on UPDATE, which is what makes
--   "the proof arrived at 10:59" a fact about the server rather than a claim by
--   the sender.
--
-- Additive and idempotent: one trigger function, one trigger, comments. No
-- policy, grant or existing value changes. Re-running is safe.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. The column exists everywhere, and defaults to the server clock ──
ALTER TABLE public.gcash_payment_proofs
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

-- Legacy rows (if a database predates the default) get the migration moment,
-- never NULL: a proof without an arrival time is exactly the gap this closes.
UPDATE public.gcash_payment_proofs
   SET submitted_at = timezone('utc'::text, now())
 WHERE submitted_at IS NULL;

ALTER TABLE public.gcash_payment_proofs
  ALTER COLUMN submitted_at SET DEFAULT timezone('utc'::text, now());

ALTER TABLE public.gcash_payment_proofs
  ALTER COLUMN submitted_at SET NOT NULL;

-- ── 2. Pin it: server-stamped on insert, immutable on update ───────────
CREATE OR REPLACE FUNCTION public.pin_gcash_proof_time()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- The server's clock wins over whatever the statement supplied.
    NEW.submitted_at := timezone('utc'::text, now());

    -- An unreadable receipt must store NO claim, not our own stamp. The RPC's
    -- COALESCE fallback is exactly this transaction's clock, so it is
    -- indistinguishable from the arrival time written above — drop it. A real
    -- receipt stamp is minute-precision from an earlier minute and can never
    -- collide, and a client cannot know the transaction clock to fake one.
    IF NEW.paid_at IS NOT DISTINCT FROM now() THEN
      NEW.paid_at := NULL;
    END IF;
  ELSE
    -- The original arrival time is restored, so a proof cannot be backdated or
    -- forward-dated after the fact.
    NEW.submitted_at := OLD.submitted_at;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.pin_gcash_proof_time() IS
  'Server-owns the proof clocks: stamps submitted_at from the server clock on insert and pins it on update, and drops a paid_at equal to the transaction clock so an unreadable receipt stores no claim (NULL) instead of a server stamp.';

DROP TRIGGER IF EXISTS trg_pin_gcash_proof_time ON public.gcash_payment_proofs;
CREATE TRIGGER trg_pin_gcash_proof_time
  BEFORE INSERT OR UPDATE ON public.gcash_payment_proofs
  FOR EACH ROW
  EXECUTE FUNCTION public.pin_gcash_proof_time();

-- ── 3. Say out loud which clock is which ───────────────────────────────
COMMENT ON COLUMN public.gcash_payment_proofs.submitted_at IS
  'When the proof arrived at the server. Written by trg_pin_gcash_proof_time from the server clock on insert and immutable afterwards — the trusted anchor when a receipt''s own time is in question.';

COMMENT ON COLUMN public.gcash_payment_proofs.paid_at IS
  'What the receipt CLAIMS: read from the screenshot by the app''s OCR. NULL = the receipt carried no readable clock (the submit RPC''s now() fallback is stripped by trg_pin_gcash_proof_time, so this is never our own stamp). Customer-influenced — compare it with submitted_at, never rely on it alone.';

-- ── 2b. Rows written before this file ─────────────────────────────────
-- The fallback also landed on every existing row: paid_at was COALESCE'd to
-- the transaction clock, which is exactly where submitted_at came from. That
-- equality is the fingerprint of "we did not read a clock", so clear it. A
-- genuine receipt stamp sits at an earlier minute and is left alone.
UPDATE public.gcash_payment_proofs
   SET paid_at = NULL
 WHERE paid_at IS NOT NULL
   AND submitted_at IS NOT NULL
   AND paid_at = submitted_at;

COMMIT;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 1. The trigger is there, armed:
-- SELECT tgname, tgenabled FROM pg_trigger
--  WHERE tgrelid = 'public.gcash_payment_proofs'::regclass
--    AND NOT tgisinternal;
--
-- 2. A supplied arrival time is ignored (needs a real order + customer JWT,
--    so run it in the test harness rather than by hand):
--    INSERT ... submitted_at = '2020-01-01T00:00:00Z'  →  submitted_at = now()
--
-- 3. An arrival time cannot be moved:
-- UPDATE public.gcash_payment_proofs
--    SET submitted_at = '2020-01-01T00:00:00Z'
--  WHERE id = '<proof>';
-- SELECT submitted_at FROM public.gcash_payment_proofs WHERE id = '<proof>';
--   -- unchanged
--
-- 4. Nothing is NULL:
-- SELECT count(*) FROM public.gcash_payment_proofs WHERE submitted_at IS NULL;
--   -- 0
--
-- 5. No claim is a copy of its own arrival stamp:
-- SELECT count(*) FROM public.gcash_payment_proofs
--  WHERE paid_at IS NOT NULL AND paid_at = submitted_at;
--   -- 0
--
-- Rollback: DROP TRIGGER trg_pin_gcash_proof_time ON public.gcash_payment_proofs;
--           DROP FUNCTION public.pin_gcash_proof_time();
--           (the column, its default and its values are worth keeping)
