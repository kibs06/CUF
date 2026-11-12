-- ══════════════════════════════════════════════════════════════════
-- Migration: the 3D model request stops asking the seller for measurements
-- Date: 2026-11-12
-- Roadmap: docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md, V2.10 (the request form)
--
-- WHY THIS CHANGE:
--   The request form asked the seller to measure the pair with a ruler — four
--   boxes in millimetres or centimetres, a measuring guide, two size pickers.
--   That was the wrong question for this market twice over: CUFMAI's sellers
--   are artisans, not metrologists, and they do not know the pair's outside
--   length to the millimetre — and the fitting does not need it either, because
--   the renderer sizes the model to each customer's foot on its own. So the
--   seller now sends a bare ask (plus an optional note), and the team models
--   from the product itself.
--
--   What changes:
--     1. `external_length_mm` becomes nullable — it was the one required
--        number, and the form no longer sends it.
--     2. Its CHECK admits NULL (still 8 CHECKs on the table, so
--        `supabase/tests/shoe_model_requests.test.sql` assertion 8 holds).
--     3. `request_shoe_model` takes `p_external_length_mm` as
--        `DEFAULT NULL` and refuses an out-of-band figure ONLY when one is
--        actually sent — a provided 40 is still a typo, while an absent one
--        is now the normal case. Same 8-argument signature (assertion 2
--        holds), same argument names, so PostgREST resolution is unchanged
--        and the app's named-argument call cannot go ambiguous.
--
--   What does NOT change, deliberately:
--     - The other four measurement columns stay: old asks keep their numbers,
--       the admin queue still shows them, and the modelling prefill still
--       reads them. NULL from here on means "not measured".
--     - A hand-written call that sends a length is still band-checked, in the
--       RPC as well as by the CHECK — the pgTAP suite's assertion 20 (40 mm
--       refused) keeps passing unchanged.
--     - The app sends `p_external_length_mm` EXPLICITLY (null when absent)
--       rather than omitting it, so a server that has not had this file
--       applied answers with the RPC's own json refusal instead of a
--       PostgREST resolution error — a sentence, not a crash.
--
-- ⚠️ WRITTEN 2026-11-12, APPLY VIA THE SQL EDITOR — never `supabase db push`.
--    The live project needs this pasted in through the SQL Editor, exactly
--    like `20260928140000` and `20260929120000`.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. The length stops being required ────────────────────────────
ALTER TABLE public.shoe_model_requests
  ALTER COLUMN external_length_mm DROP NOT NULL;

-- The house shape (DROP then ADD, both idempotent): a re-run converges
-- instead of erroring on a constraint that is already correct, and the table
-- keeps exactly the CHECKs the pgTAP suite counts.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_external_length_mm_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_external_length_mm_check
  CHECK (external_length_mm IS NULL OR external_length_mm BETWEEN 100 AND 400);

COMMENT ON COLUMN public.shoe_model_requests.external_length_mm IS
  'The pair''s outside length in mm, heel to toe — the figure the renderer scales to. Optional since 2026-11-12: the seller no longer measures anything, so a NULL here means "asked without measuring" rather than "missing".';

-- ── 2. The RPC: the length is taken, not demanded ─────────────────
DROP FUNCTION IF EXISTS public.request_shoe_model(
  uuid, numeric, numeric, numeric, numeric, text, numeric, numeric[]
);

CREATE OR REPLACE FUNCTION public.request_shoe_model(
  p_product_id         uuid,
  p_external_length_mm numeric DEFAULT NULL,
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
  -- this function (the 42804 trap that cost this flow a CI run on 2026-09-28).
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

  -- A figure that IS sent is still band-checked: 40 mm is a typo, not a shoe.
  -- But nothing is demanded any more — the form sends no measurements, and the
  -- team models from the product itself.
  IF p_external_length_mm IS NOT NULL
     AND (p_external_length_mm < 100 OR p_external_length_mm > 400) THEN
    RETURN json_build_object(
      'success', false,
      'message', 'That length does not look right — an outside length should be somewhere between 100 and 400 mm. Leave it out if you are not sure.'
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
  -- ordered and stripped of anything outside the band (the chips cannot produce
  -- a bad run, so this is the guard for a hand-written call).
  IF p_sizes_eu IS NOT NULL THEN
    SELECT array_agg(DISTINCT s ORDER BY s)
      INTO v_sizes
      FROM unnest(p_sizes_eu) AS s
     WHERE s BETWEEN 22 AND 48;

    -- Everything filtered out, so the run said nothing usable. Treated as "not
    -- stated" rather than as an error.
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
   (uq_shoe_model_requests_open). Since 2026-11-12 the seller sends no ruler
   measurements — the length and friends are all optional, band-checked only
   when actually sent — and the team models from the product itself.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying, through the SQL Editor or
-- `supabase db query --linked` — never `supabase db push`)
--
-- The length is nullable (must list 1 row, YES):
--   select column_name, is_nullable from information_schema.columns
--    where table_name = 'shoe_model_requests'
--      and column_name = 'external_length_mm';
--
-- Still exactly 8 CHECKs (must count 8 — pgTAP assertion 8):
--   select count(*) from pg_constraint
--    where conrelid = 'public.shoe_model_requests'::regclass and contype = 'c';
--
-- Still the one 8-argument signature (pgTAP assertion 2):
--   select oid::regprocedure from pg_proc
--    where proname = 'request_shoe_model'
--      and pronamespace = 'public'::regnamespace;
--
-- A bare ask succeeds and stores NULLs (run as a store owner, then roll back):
--   begin;
--   select public.request_shoe_model('<a product id you own>'::uuid);
--   select external_length_mm, external_width_mm, heel_height_mm,
--          upper_height_mm, measured_size_eu, sizes_eu
--     from public.shoe_model_requests where product_id = '<it>';
--   rollback;
--
-- A sent 40 is still refused (pgTAP assertion 20 covers this in CI):
--   begin;
--   select public.request_shoe_model('<a product id you own>'::uuid, 40.0);
--   rollback;
--
-- Full proof-of-behaviour, including the new bare ask:
-- supabase/tests/shoe_model_requests.test.sql
-- ══════════════════════════════════════════════════════════════════
