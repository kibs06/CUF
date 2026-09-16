-- ══════════════════════════════════════════════════════════════════════
-- Pickup codes — the customer shows a code, the seller finds and fulfils the
-- hold in one action (ANQUI item 14 follow-up)
-- ══════════════════════════════════════════════════════════════════════
-- Until now a hold was identified by a UUID. That works for the app and for
-- nobody at a counter: the customer and the seller are standing next to each
-- other, and "which of these holds is the one in front of me?" had no answer
-- that did not involve scrolling a list together.
--
-- So each hold gets a six-character code, derived from an alphabet with no
-- ambiguous characters, shown to the customer on their reservation and typed in
-- (or read aloud) by the seller to select that exact hold. The code is NOT a
-- secret and NOT an authorization boundary — see §4 — it is a LOOKUP KEY for
-- the person already authorized to act on the hold.
--
-- WHY A CODE AND NOT A QR IMAGE: rendering a QR needs a renderer dependency this
-- app does not have (`mobile_scanner` scans, it does not draw). The code is the
-- payload a QR would carry, so adding one later is a presentation change: the
-- customer's screen would render the code it already shows, and the seller's
-- scanner — `mobile_scanner` around `pos_barcode_scanner.dart` — would decode
-- the same string this file already accepts. Nothing here has to change.
--
-- ⚠️ REQUIRES §3 of `20260915170000_add_pickup_reservations.sql` (the
-- `pickup_code` column + its CHECK + the unique index). That file is already in
-- the re-apply list; the column lives THERE rather than here because a code is
-- part of what a hold IS, exactly like `store_extension_count`.
-- ══════════════════════════════════════════════════════════════════════

-- 1. THE SHAPE, AS NUMBERS ────────────────────────────────────────────
-- Exposed as functions so the generator, the pgTAP suite, the Dart constants
-- and the docs read ONE definition each, and so the contract test can pin them
-- against the literal regex in the column CHECK rather than trusting a copy.
--
-- The alphabet omits I, L, O, U, 0 and 1 on purpose. A pickup code is read off a
-- phone screen across a counter and often spoken aloud, and those six are the
-- ones that turn into each other: 1/I/l, 0/O, and a U that gets written as V.
-- 30 symbols is still far more namespace than this feature can consume.
CREATE OR REPLACE FUNCTION public.pickup_code_alphabet()
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$ SELECT '23456789ABCDEFGHJKMNPQRSTVWXYZ'; $$;

COMMENT ON FUNCTION public.pickup_code_alphabet() IS
  'The 30 symbols a pickup code is drawn from: digits 2-9 and A-Z without I, L, O and U. Mirrored by PickupReservation.codeAlphabet in Dart and pinned to the column CHECK by test/services/pickup_reservation_contract_test.dart.';

CREATE OR REPLACE FUNCTION public.pickup_code_length()
RETURNS integer
LANGUAGE sql IMMUTABLE
AS $$ SELECT 6; $$;

COMMENT ON FUNCTION public.pickup_code_length() IS
  'Characters in a pickup code. Six over a 30-symbol alphabet: short enough to read aloud, ~729M combinations against a table that holds a few thousand rows.';

-- 2. THE GENERATOR ────────────────────────────────────────────────────
-- Loop-until-free rather than "generate and hope": the unique index is the
-- backstop, but a collision AT INSERT would fail the customer's request with a
-- 23505 that has nothing to do with anything they did. The loop makes a
-- collision invisible instead of fatal.
--
-- Randomness comes from `gen_random_uuid()` (built-in, OS-seeded) hashed, not
-- from `random()`: `random()` is session-seeded, so a burst of inserts in one
-- transaction could draw the same stream. A code is not a secret and does not
-- need cryptographic strength, but two holds sharing six characters by accident
-- is a bug in a feature whose whole job is telling two holds apart.
CREATE OR REPLACE FUNCTION public.generate_pickup_code()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_alphabet text    := public.pickup_code_alphabet();
    v_len      integer := public.pickup_code_length();
    v_hash     text;
    v_code     text;
    v_try      integer := 0;
BEGIN
    LOOP
        v_try  := v_try + 1;
        v_hash := md5(gen_random_uuid()::text);
        v_code := '';
        FOR i IN 1 .. v_len LOOP
            -- One hex byte per character, folded into the alphabet. The fold is
            -- not perfectly uniform (256 is not a multiple of 30); that only
            -- shifts the odds of a symbol, and a code is a lookup key rather
            -- than a token, so it is deliberately not worth more machinery.
            v_code := v_code || substr(
                v_alphabet,
                (get_byte(decode(v_hash, 'hex'), i - 1) % length(v_alphabet)) + 1,
                1);
        END LOOP;

        IF NOT EXISTS (
            SELECT 1 FROM public.pickup_reservations WHERE pickup_code = v_code
        ) THEN
            RETURN v_code;
        END IF;

        -- Unreachable in practice (a collision needs a 1-in-729M draw). Bounded
        -- so a future change that makes codes deterministic fails loudly here
        -- instead of spinning forever.
        IF v_try >= 25 THEN
            RAISE EXCEPTION
                'PICKUP_CODE_EXHAUSTED — no free code in % attempts', v_try;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.generate_pickup_code() IS
  'Returns a pickup code not currently in use. Loops rather than relying on the unique index, so a collision can never surface as a failed customer request.';

-- 2b. NORMALISATION ───────────────────────────────────────────────────
-- What the seller types and what the customer reads are not what gets stored:
-- "4f 7k-2q" is "4F7K2Q". Deliberately only strips separators and case — it
-- does NOT substitute look-alikes (an O is not rewritten to a zero), because a
-- silent substitution would turn a mistyped code into somebody else's hold.
-- Anything that is not a 6-character code after normalisation simply does not
-- match, and the caller is told NOT_FOUND.
CREATE OR REPLACE FUNCTION public.normalize_pickup_code(p_code text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
    SELECT upper(regexp_replace(
        btrim(COALESCE(p_code, '')), '[^A-Za-z0-9]', '', 'g'));
$$;

COMMENT ON FUNCTION public.normalize_pickup_code(text) IS
  'Upper-cases a typed or read-out pickup code and strips separators. Performs no look-alike substitution, so a wrong code can never normalise into a right one.';

-- 3. EVERY HOLD GETS ONE ──────────────────────────────────────────────
-- A BEFORE INSERT trigger rather than a line in `request_pickup_reservation`:
-- the code is part of the row, so any insert path — the RPC today, a future
-- flow, a hand-written repair — gets one, and there is exactly one place that
-- decides the format.
CREATE OR REPLACE FUNCTION public.assign_pickup_code()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.pickup_code IS NULL OR btrim(NEW.pickup_code) = '' THEN
        NEW.pickup_code := public.generate_pickup_code();
    ELSE
        -- A code supplied by an insert is normalised, then validated by the
        -- column CHECK like any other. Normalising rather than rejecting keeps
        -- a re-apply of an older row idempotent.
        NEW.pickup_code := public.normalize_pickup_code(NEW.pickup_code);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pickup_reservations_assign_code
    ON public.pickup_reservations;
CREATE TRIGGER trg_pickup_reservations_assign_code
    BEFORE INSERT ON public.pickup_reservations
    FOR EACH ROW
    EXECUTE FUNCTION public.assign_pickup_code();

COMMENT ON FUNCTION public.assign_pickup_code() IS
  'BEFORE INSERT: fills in a pickup code when none was given. Keeps the code format in one place and guarantees no hold exists without one.';

-- 3b. AND THE HOLDS THAT ALREADY EXIST DO TOO ─────────────────────────
-- The live table has rows predating this column, and a hold without a code
-- cannot be looked up at a counter — which is the entire feature. Backfilled
-- row by row (rather than one set-based UPDATE) so each call to
-- `generate_pickup_code()` sees the codes assigned before it.
DO $$
DECLARE
    v_id uuid;
    v_count integer := 0;
BEGIN
    FOR v_id IN
        SELECT id FROM public.pickup_reservations WHERE pickup_code IS NULL
    LOOP
        UPDATE public.pickup_reservations
        SET pickup_code = public.generate_pickup_code()
        WHERE id = v_id;
        v_count := v_count + 1;
    END LOOP;
    RAISE NOTICE 'Backfilled % pickup code(s)', v_count;
END
$$;

-- 4. RESOLVE A CODE → A HOLD (store-scoped, deliberately narrow) ───────
-- Returns the hold's id, and ONLY for a store the caller owns. The code is not
-- a security boundary — knowing one reveals nothing and permits nothing — but
-- WITHOUT this scoping any seller could enumerate codes and pull up another
-- store's holds, which is somebody else's business (who is holding what, and
-- when they are coming to collect it). So the query is joined through
-- `stores.owner_id = auth.uid()` and a code that belongs to another store is
-- reported exactly like a code that does not exist, so the error cannot be used
-- to probe for real codes.
--
-- A RESOLVED hold resolves too (the check is on ownership, not on status): a
-- disputed collection — "this is the pair the customer showed me" — is exactly
-- when a seller needs the trail, and the caller sees `status` on the row and can
-- say "already collected" instead of the lookup silently failing.
CREATE OR REPLACE FUNCTION public.find_pickup_reservation_by_code(p_code text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor uuid := auth.uid();
    v_code  text := public.normalize_pickup_code(p_code);
    v_id    uuid;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    IF length(v_code) <> public.pickup_code_length() THEN
        RAISE EXCEPTION
            'NOT_FOUND — no pickup hold matches that code (a code is % characters)',
            public.pickup_code_length();
    END IF;

    SELECT r.id INTO v_id
    FROM public.pickup_reservations r
    JOIN public.stores s ON s.id = r.store_id
    WHERE r.pickup_code = v_code
      AND s.owner_id = v_actor
    LIMIT 1;

    IF v_id IS NULL THEN
        RAISE EXCEPTION
            'NOT_FOUND — no pickup hold for your store matches that code';
    END IF;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.find_pickup_reservation_by_code FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_pickup_reservation_by_code TO authenticated;

COMMENT ON FUNCTION public.find_pickup_reservation_by_code(text) IS
  'Resolves a counter code to a hold id, for the store that owns the hold only. Another store''s code reads as NOT_FOUND, so the error cannot be probed for real codes.';

-- 5. ONE ACTION AT THE COUNTER ────────────────────────────────────────
-- The seller types the code and the hold is collected. This is a RESOLVER plus a
-- delegation, not a second implementation: `fulfill_pickup_reservation` still
-- owns the ownership check, the ALREADY_RESOLVED guard, the POS order and the
-- single stock draw, so a rule added there cannot be forgotten here. The only
-- thing this adds is the lookup.
CREATE OR REPLACE FUNCTION public.fulfill_pickup_reservation_by_code(
    p_code text,
    p_payment_method text DEFAULT 'cash'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id uuid;
BEGIN
    v_id := public.find_pickup_reservation_by_code(p_code);
    RETURN public.fulfill_pickup_reservation(v_id, p_payment_method);
END;
$$;

REVOKE ALL ON FUNCTION public.fulfill_pickup_reservation_by_code(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fulfill_pickup_reservation_by_code(text, text) TO authenticated;

COMMENT ON FUNCTION public.fulfill_pickup_reservation_by_code(text, text) IS
  'Collects a hold from its counter code in one call: resolves the code for the caller''s store, then delegates to fulfill_pickup_reservation so every fulfilment rule stays in one place.';

-- No new table and no new RLS surface, so there is nothing to fold into the
-- device gate here — the new functions are SECURITY DEFINER with their own
-- ownership checks, and both are revoked from `anon`.

-- ══════════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════════
-- One definition of the shape, and the same one the column CHECK enforces:
--   select public.pickup_code_alphabet();   -- 23456789ABCDEFGHJKMNPQRSTVWXYZ
--   select public.pickup_code_length();     -- 6
--
-- A code looks like a code, and no two share one:
--   select count(*) from public.pickup_reservations where pickup_code is null;  -- 0
--   select count(*), count(distinct pickup_code) from public.pickup_reservations;
--
-- Normalisation is forgiving about how it is written and strict about what it
-- accepts:
--   select public.normalize_pickup_code(' 4f 7k-2q ');   -- 4F7K2Q
--   select public.normalize_pickup_code('OOPS');         -- OOPS (5 chars → NOT_FOUND)
--
-- The counter flow, as the store owner:
--   select public.find_pickup_reservation_by_code('4F7K2Q');        -- the hold id
--   select public.fulfill_pickup_reservation_by_code('4F7K2Q');     -- the POS order id
--
-- The backfill (must report 0 remaining):
--   select count(*) from public.pickup_reservations where pickup_code is null;
--
-- Full proof-of-behaviour: supabase/tests/pickup_codes.test.sql.
