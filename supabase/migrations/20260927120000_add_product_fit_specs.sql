-- ══════════════════════════════════════════════════════════════════
-- Migration: product fit specs — the four numbers the fit engine needs
-- Date: 2026-09-27
--
-- ── Why this exists ───────────────────────────────────────────────
-- `lib/utils/fit_engine.dart` turns a customer's foot millimetres and a
-- product's **internal last** millimetres into a size verdict
-- (docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md §2.6). Until now the
-- catalog carried no length number at all: sizes existed only as strings
-- in `inventory.size`, so the app could say "we stock EU 42" and nothing
-- about whether EU 42 fits the person reading the page. These four
-- nullable columns are that missing input.
--
-- ── The contract these columns carry (architecture §2.5.1 / §2.7.3) ─
-- `last_length_mm` is the **internal** length of the shoe's last at
-- `fit_ref_size_eu` — measured inside the shoe, heel to toe, the same
-- axis a foot occupies. It is deliberately NOT the mesh's external
-- heel-to-toe length (`product_models.authored_length_mm`, V2): leather
-- and the upper's thickness make the external figure 8–15 mm longer, and
-- mixing the two would hand every customer a verdict one full size too
-- generous. The two numbers never share a column.
--
-- ── Why nullable, with no backfill (decision D7) ───────────────────
-- No existing product has these numbers and no amount of migration can
-- invent them: a last length is a physical measurement of a real pair.
-- Nullable columns make the rollout honest — products without specs
-- simply produce no verdict (the engine returns null rather than a
-- guess), and the seller form (roadmap V1.4) starts filling them in
-- from the next listing onward.
--
-- ── Why `fit_ref_size_eu` has no DEFAULT ──────────────────────────
-- §2.7.3 sketched "(default 42)". It does not get one: the reference
-- size is a *fact about the sample that was measured*, not a convention.
-- A default would silently attach "42" to a seller who measured their
-- EU 39 pair and never filled the field, and then grade every size from
-- a number that is three sizes wrong. Missing means missing — the engine
-- treats it as "no specs" and reports nothing.
--
-- ── Why the CHECKs ────────────────────────────────────────────────
-- They mirror the plausibility bounds the engine itself enforces
-- (`kPlausibleLastLengthMm`, `kPlausibleEuMin/Max` in `size_key.dart`),
-- so a typo'd `4200` cannot even be saved. The widest legitimate case is
-- a kids' EU 22 last (~135 mm) and the EU 48 end (~330 mm); the bounds
-- are deliberately looser than that so a real outlier still fits.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS last_length_mm  NUMERIC,
  ADD COLUMN IF NOT EXISTS last_width_mm   NUMERIC,
  ADD COLUMN IF NOT EXISTS heel_height_mm  NUMERIC,
  ADD COLUMN IF NOT EXISTS fit_ref_size_eu NUMERIC;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_last_length_mm_check,
  DROP CONSTRAINT IF EXISTS products_last_width_mm_check,
  DROP CONSTRAINT IF EXISTS products_heel_height_mm_check,
  DROP CONSTRAINT IF EXISTS products_fit_ref_size_eu_check;

ALTER TABLE public.products
  ADD CONSTRAINT products_last_length_mm_check
    CHECK (last_length_mm IS NULL OR (last_length_mm BETWEEN 120 AND 360)),
  ADD CONSTRAINT products_last_width_mm_check
    CHECK (last_width_mm IS NULL OR (last_width_mm BETWEEN 40 AND 140)),
  ADD CONSTRAINT products_heel_height_mm_check
    CHECK (heel_height_mm IS NULL OR (heel_height_mm BETWEEN 0 AND 80)),
  -- The same band `kPlausibleEuMin/Max` uses: outside it a stored size is
  -- treated as an unknown system rather than silently read as EU.
  ADD CONSTRAINT products_fit_ref_size_eu_check
    CHECK (fit_ref_size_eu IS NULL OR (fit_ref_size_eu BETWEEN 22 AND 48));

-- A product with a length but no reference size cannot produce a verdict,
-- so the pair is all-or-nothing at the database level too. The engine
-- rejects the half-filled shape anyway; this keeps it from ever existing.
ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_fit_length_needs_ref_size_check;

ALTER TABLE public.products
  ADD CONSTRAINT products_fit_length_needs_ref_size_check
    CHECK (
      last_length_mm IS NULL
      OR fit_ref_size_eu IS NOT NULL
    );

COMMENT ON COLUMN public.products.last_length_mm IS
  'INTERNAL last length in mm (heel to toe, inside the shoe) at fit_ref_size_eu. Drives the fit verdict; NOT the mesh external length (product_models.authored_length_mm).';
COMMENT ON COLUMN public.products.last_width_mm IS
  'INTERNAL last width in mm at fit_ref_size_eu. Optional: without it the verdict compares length only and says so.';
COMMENT ON COLUMN public.products.heel_height_mm IS
  'Heel/stack height in mm. Carried for later silhouette and verdict nuance; the current bands do not read it.';
COMMENT ON COLUMN public.products.fit_ref_size_eu IS
  'The EU size the last_*_mm values were measured at. No default: a missing value means "unknown", never 42.';
