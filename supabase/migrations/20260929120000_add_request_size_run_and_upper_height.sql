-- ══════════════════════════════════════════════════════════════════
-- Migration: the 3D-fitting request asks two more questions, and stores both
-- Date: 2026-09-29
-- Roadmap: docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md, V2.10 (the request form)
--
-- WHY THIS CHANGE:
--   V2.10's request sheet asked for one required number and three optional ones,
--   and the four of them are all about *the pair on the bench*. Two things were
--   missing from it, and neither is a new modelling requirement — both are
--   about the person holding the ruler:
--
--   1. `sizes_eu` — **every size this shoe is made in**, not just the one that
--      was measured. The seller knows this without measuring anything; it is
--      the shape of their catalogue. Nothing in the pipeline scales from it:
--      one model serves every size, and the renderer grades the mesh per EU
--      size from the fit spec (architecture §2.5.2's 6.67 mm step). What the
--      run buys is the *team's* check — a modeller can put the model beside the
--      sizes actually sold instead of the single pair that happened to be on the
--      bench, and a run the mesh cannot serve is a question asked before
--      publish rather than after.
--
--   2. `upper_height_mm` — the shoe's overall height, sole to its highest point.
--      The authoring contract already checks the mesh's length, up-axis and
--      grounding; it checks no height at all, so a declared one is a second
--      opinion rather than a restatement of a number the validator already has.
--      It is also the only dimension in the sheet that distinguishes a sandal
--      from a boot at a glance, which is exactly the silhouette decision a
--      try-on gets asked about.
--
--   ⚠️ **Both are optional, and that is load-bearing rather than polite.** The
--   columns are nullable, the RPC's new arguments carry `DEFAULT NULL`, and the
--   Dart caller sends them only when they hold something
--   (`shoe_model_request_service.dart`). PostgREST resolves a function by its
--   argument names, so naming an argument a server does not have yet fails the
--   *whole* call — which means a seller who ignores both new boxes keeps sending
--   exactly the payload that works against the previous revision. The new fields
--   start working the moment this file is applied, and nothing breaks before it.
--
-- ⚠️ THE FUNCTION IS DROPPED AND RECREATED RATHER THAN REPLACED, AND THAT IS
--    DELIBERATE. `CREATE OR REPLACE FUNCTION` cannot change an argument list:
--    adding two parameters would create an OVERLOAD beside the six-argument
--    original, and a named-argument call from the app would then be ambiguous
--    between them ("function request_shoe_model(...) is not unique"). So the
--    six-argument function is dropped first, and the eight-argument one —
--    six unchanged plus two defaulted — takes its place. `DROP … IF EXISTS`
--    makes a re-run converge.
--
-- ⚠️ AND ONE ORDERING HAZARD, recorded here because it is invisible from this
--    file: `supabase/manual/20260928140000_add_shoe_model_requests.apply.sql`
--    embeds the OLD six-argument `request_shoe_model`. Re-applying that bundle
--    *after* this file would recreate the overload this file just removed. It
--    does not need re-applying — it is already live and verified — so the rule
--    is simply: apply this one second, and do not re-paste the old bundle.
--
-- ⚠️ WRITTEN 2026-09-29, APPLY VIA THE SQL EDITOR — never `supabase db push`.
--    The live project needs this pasted in through the SQL Editor, exactly like
--    `20260928140000`.
--
-- ⚠️ AND THE FIRST PASTE OF THIS FILE IS WHAT TAUGHT IT SOMETHING, so the
--    timeline is recorded rather than assumed: it was written expecting CI to be
--    its first execution, and the paste was. It failed at the `sizes_eu` CHECK
--    with `0A000: cannot use subquery in check constraint` — the element-wise
--    test of an array cannot be a subquery inside a constraint, and
--    `array_length` cannot see an empty array either. Both traps are written up
--    beside that constraint and the element-wise half now lives in
--    `public.numeric_array_within_band(...)`. The lesson is the one
--    `MIGRATIONS_LIVE_STATUS.md` keeps repeating in the other direction: a file
--    that has never run has never been tested, whatever CI is configured to do.
--
-- ⚠️ AND IT BREAKS TWO pgTAP ASSERTIONS BY DESIGN, both updated in the same
--    change so CI stays green: `shoe_model_requests.test.sql` assertion 2 pinned
--    the SIX-argument signature this file drops, and assertion 8 counted six
--    CHECK constraints where there are now eight. New assertions 61–76 cover
--    the two columns, both bands, the run's canonicalisation and the helper's
--    edges.
-- ══════════════════════════════════════════════════════════════════

-- ── The two columns ──────────────────────────────────────────────
-- Inline `ADD COLUMN IF NOT EXISTS` plus DROP/ADD for each CHECK, the house
-- shape: a second run converges instead of erroring on a constraint that is
-- already correct.
ALTER TABLE public.shoe_model_requests
  ADD COLUMN IF NOT EXISTS upper_height_mm numeric,
  ADD COLUMN IF NOT EXISTS sizes_eu       numeric[];

-- ── The element-wise half of the run's CHECK ──────────────────────
-- ⚠️ BEFORE the constraint that calls it, not after: `ADD CONSTRAINT` resolves
--    the function when it validates the table, so a helper defined below the
--    CHECK it belongs to fails the whole file with 42883.
--
-- `IMMUTABLE` is not an optimisation, it is the licence: Postgres refuses a CHECK
-- that calls a function it cannot prove constant for the same row.
--
-- ⚠️ Deliberately NOT `STRICT`, and deliberately `coalesce(..., false)`. A CHECK
-- is satisfied by NULL, so a helper that answered NULL for an empty or an
-- all-NULL array would let exactly the values this guards against through the
-- door. This one answers true or false and nothing else — including for the
-- empty array, so the `cardinality` test further down is a named requirement
-- rather than the only thing standing between `{}` and the column.
--
-- The band is CONTINUOUS (22–48), matching the Dart constant
-- (`kRequestEuSizeMin/Max`) rather than the picker's 53 whole-and-half chips: a
-- half size the picker never offers is a size this column should not refuse on
-- the picker's behalf, and a 53-value literal here would be a second copy of a
-- list that already lives in Dart.
CREATE OR REPLACE FUNCTION public.numeric_array_within_band(
  p_values numeric[],
  p_min    numeric,
  p_max    numeric
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(
           bool_and(v IS NOT NULL AND v BETWEEN p_min AND p_max),
           false
         )
    FROM unnest(p_values) AS v;
$$;

COMMENT ON FUNCTION public.numeric_array_within_band(numeric[], numeric, numeric) IS
  'True when every element of the array is non-null and inside [p_min, p_max].
   Exists because a CHECK constraint may not contain a subquery (0A000), so the
   element-wise test of shoe_model_requests.sizes_eu has to be a function;
   IMMUTABLE so a CHECK may call it, and never NULL so a CHECK cannot pass on
   it. Do not drop without CASCADE - the sizes_eu CHECK depends on it.';

-- The band mirrors `kRequestUpperHeightMinMm/MaxMm` in
-- `lib/utils/shoe_model_request.dart` — 10 mm is shorter than any wearable
-- shoe's collar and 400 mm is taller than the boots this shop makes, so a figure
-- outside it is a data-entry error. Nullable, because "not measured" is a valid
-- answer to an optional question.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_upper_height_mm_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_upper_height_mm_check
  CHECK (upper_height_mm IS NULL OR upper_height_mm BETWEEN 10 AND 400);

-- ⚠️ The run is checked element by element, in the database as well as in Dart,
-- for the same reason every other band is: the RPC is a public door, and a
-- hand-written call must not be able to store `[0, 99]` in a column the admin
-- queue renders as fact. An EMPTY array is refused too — `{}` is a claim that
-- the shoe is made in no sizes, and `NULL` is the honest way to say "not stated".
--
-- ⚠️ TWO TRAPS HERE, both found by pasting the file rather than by reading it —
--    recorded because this is the one place in the schema where the obvious
--    writing of a CHECK constraint is not legal or not true:
--
--    1. **A CHECK cannot contain a subquery.** The natural element-wise test is
--       `(SELECT bool_and(s BETWEEN 22 AND 48) FROM unnest(sizes_eu) AS s)`, and
--       Postgres refuses the whole statement: `0A000: cannot use subquery in
--       check constraint`. A constraint expression has to be a function of the
--       row alone, so the element-wise half lives in
--       [numeric_array_within_band] above — IMMUTABLE, which is the licence a
--       CHECK needs to call anything at all, and defined BEFORE this constraint
--       for the same reason: `ADD CONSTRAINT` resolves it there and then.
--
--    2. **`array_length` cannot see an empty array.** `array_length('{}', 1)` is
--       NULL, `NULL BETWEEN 1 AND 40` is NULL, and a CHECK treats NULL as
--       satisfied — so the "empty is refused" claim above was false as first
--       written. `cardinality` answers 0 for `{}`, which is a real answer.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_sizes_eu_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_sizes_eu_check
  CHECK (
    sizes_eu IS NULL
    OR (
      cardinality(sizes_eu) BETWEEN 1 AND 40
      AND public.numeric_array_within_band(sizes_eu, 22, 48)
    )
  );

COMMENT ON COLUMN public.shoe_model_requests.upper_height_mm IS
  'The pair''s overall height in mm, sole to its highest point — one of the four ruler measurements the seller sends. Optional. The authoring contract checks the mesh''s length, up-axis and grounding but no height, so this is a second opinion rather than a duplicate.';

COMMENT ON COLUMN public.shoe_model_requests.sizes_eu IS
  'Every EU size this shoe is made in, as the seller states it. Optional, and nothing scales from it: one model serves every size (the renderer grades per EU size from the fit spec). The team reads it to check the model against the sizes actually sold. NULL means "not stated"; an empty array is refused.';

-- ── RPC: file the ask (seller) — now with the run and the height ─
DROP FUNCTION IF EXISTS public.request_shoe_model(
  uuid, numeric, numeric, numeric, numeric, text
);

CREATE OR REPLACE FUNCTION public.request_shoe_model(
  p_product_id         uuid,
  p_external_length_mm numeric,
  p_external_width_mm  numeric DEFAULT NULL,
  p_heel_height_mm     numeric DEFAULT NULL,
  p_measured_size_eu   numeric DEFAULT NULL,
  p_note               text    DEFAULT NULL,
  p_upper_height_mm    numeric DEFAULT NULL,
  p_sizes_eu           numeric[] DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_store_id uuid;
  v_owner    uuid;
  v_open     uuid;
  -- ⚠️ BIGINT, like `product_models.id` itself — NOT uuid like every other id in
  -- this function. The SELECT below only assigns it when it FINDS a live model,
  -- so getting this wrong hides behind the common path: asking about a product
  -- without one works perfectly, and asking about a product WITH one raises
  -- `invalid input syntax for type uuid: "2"` (the 42804 trap that cost this
  -- flow a CI run on 2026-09-28).
  v_live     bigint;
  v_new_id   uuid;
  v_sizes    numeric[];
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- The product must exist, and the caller must own its store (admins file asks
  -- on a seller's behalf, which is how a phone call becomes a row).
  SELECT p.store_id, s.owner_id INTO v_store_id, v_owner
    FROM public.products p
    JOIN public.stores s ON s.id = p.store_id
   WHERE p.id = p_product_id;

  IF v_store_id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'That product no longer exists.');
  END IF;

  IF v_owner <> v_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only the store owner can request a 3D model'
      USING ERRCODE = '42501';
  END IF;

  -- Asked in the seller's own language, so the sentence says what to do.
  IF p_external_length_mm IS NULL
     OR p_external_length_mm < 100
     OR p_external_length_mm > 400 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Measure the pair from the back of the heel to the tip of the toe and enter it in millimetres — it should be somewhere between 100 and 400 mm.'
    );
  END IF;

  -- The same sentence for the height, because it is the same kind of mistake:
  -- a number outside the band is a slip, not a very tall sandal.
  IF p_upper_height_mm IS NOT NULL
     AND (p_upper_height_mm < 10 OR p_upper_height_mm > 400) THEN
    RETURN json_build_object(
      'success', false,
      'message', 'The height of the shoe should be between 10 and 400 mm — sole to the highest point.'
    );
  END IF;

  -- ⚠️ The run is CANONICALISED here rather than stored as sent: deduplicated,
  -- ordered and stripped of anything outside the band. The chips cannot produce
  -- a bad run, so this is the guard for a hand-written call, and doing it in the
  -- function means the column's CHECK is a backstop rather than the only line —
  -- a request that carries a stray `0` is trimmed to the sizes that are real
  -- instead of being refused over a value the seller never chose.
  IF p_sizes_eu IS NOT NULL THEN
    SELECT array_agg(DISTINCT s ORDER BY s)
      INTO v_sizes
      FROM unnest(p_sizes_eu) AS s
     WHERE s BETWEEN 22 AND 48;

    -- Everything filtered out, so the run said nothing usable. Treated as "not
    -- stated" rather than as an error: the seller answered a question they were
    -- not required to answer, and refusing the whole request over it would lose
    -- the measurement that matters.
    IF v_sizes IS NULL OR array_length(v_sizes, 1) = 0 THEN
      v_sizes := NULL;
    END IF;
  END IF;

  -- Already has one live: nothing to ask for.
  SELECT pm.id INTO v_live
    FROM public.product_models pm
   WHERE pm.product_id = p_product_id
     AND pm.status = 'active'
   LIMIT 1;

  IF v_live IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'This product already has a 3D model attached, so there is nothing to request.'
    );
  END IF;

  -- The partial unique index would raise 23505; answering in json keeps the
  -- message one the seller can act on instead of a constraint name.
  SELECT r.id INTO v_open
    FROM public.shoe_model_requests r
   WHERE r.product_id = p_product_id
     AND r.status IN ('requested', 'in_progress')
   LIMIT 1;

  IF v_open IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'You have already asked for a 3D model for this product. It is with the CUFMAI team.'
    );
  END IF;

  INSERT INTO public.shoe_model_requests (
    product_id, store_id, requested_by,
    external_length_mm, external_width_mm, heel_height_mm,
    upper_height_mm, measured_size_eu, sizes_eu, note
  ) VALUES (
    p_product_id, v_store_id, v_user_id,
    p_external_length_mm, p_external_width_mm, p_heel_height_mm,
    p_upper_height_mm, p_measured_size_eu, v_sizes,
    nullif(btrim(coalesce(p_note, '')), '')
  )
  RETURNING id INTO v_new_id;

  RETURN json_build_object(
    'success', true,
    'request_id', v_new_id,
    'message', 'Request sent. The CUFMAI team will build the 3D model for this product and let you know here when it is ready.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.request_shoe_model(
    uuid, numeric, numeric, numeric, numeric, text, numeric, numeric[]
  )
  TO authenticated;

COMMENT ON FUNCTION
  public.request_shoe_model(
    uuid, numeric, numeric, numeric, numeric, text, numeric, numeric[]
  ) IS
  'Seller-filed ask for a modelled 3D shoe. Refuses a product that already has
   an active model, and refuses a second open request for the same product
   (uq_shoe_model_requests_open). Takes the EXTERNAL length in millimetres —
   the figure the renderer scales to, not the internal last length the fit
   verdict uses — plus, optionally, the pair''s overall height and the size run
   the shoe is made in (canonicalised: deduplicated, ordered, in-band).';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying, through the SQL Editor or
-- `supabase db query --linked` — never `supabase db push`)
--
-- Both columns exist and are nullable (must list 2 rows, both YES):
--   select column_name, is_nullable from information_schema.columns
--    where table_name = 'shoe_model_requests'
--      and column_name in ('upper_height_mm', 'sizes_eu');
--
-- Both CHECKs are present (must list 2):
--   select conname from pg_constraint
--    where conrelid = 'public.shoe_model_requests'::regclass
--      and conname in ('shoe_model_requests_upper_height_mm_check',
--                      'shoe_model_requests_sizes_eu_check');
--
-- ⚠️ The element-wise helper the run's CHECK calls is present and immutable
--    (must be 1 row, ending in `numeric_array_within_band(numeric[],numeric,numeric)`):
--   select p.oid::regprocedure from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'numeric_array_within_band'
--      and p.provolatile = 'i';
--
-- ⚠️ The overload is gone and only the eight-argument function remains —
--    this is the check that earns its keep, because a leftover six-argument
--    function makes the app's named-argument call ambiguous (must be 1 row,
--    with the eight-argument signature):
--   select p.oid::regprocedure from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'request_shoe_model';
--
-- The queue still holds what it held (informational):
--   select count(*) from public.shoe_model_requests;
--
-- Full proof-of-behaviour, including the two new bands and the run's
-- canonicalisation:
-- supabase/tests/shoe_model_requests.test.sql
-- ══════════════════════════════════════════════════════════════════
