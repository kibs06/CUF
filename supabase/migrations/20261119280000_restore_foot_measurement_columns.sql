-- Restore the live-AR confidence columns on public.foot_measurements.
--
-- WHY THIS FILE EXISTS
-- "Save to Profile" on the card-scan results screen failed with the generic
-- "Failed to save — please try again." for EVERY scan, good or bad.
-- FootMeasurement.toInsertMap() (lib/models/foot_measurement.dart) names all
-- six columns below on every insert — null or not — and PostgREST refuses an
-- INSERT that names a column the table does not have (PGRST204, "Could not
-- find the 'length_confidence_left' column … in the schema cache"). The
-- service swallows that error and returns null, so the screen could only show
-- the generic sentence.
--
-- 20260730100000_add_foot_measurements.sql creates these columns; the hosted
-- project (psczvbfoybqhjeqssimw) drifted and no longer has them. Verified on
-- 2026-11-19 by reading information_schema: the table carries id, user_id, the
-- raw and compensated mm columns, sizes, paper_size_used, foot_condition,
-- user_adjusted_eu_size, paper_detection_confidence, lighting_quality,
-- scan_date, created_at, sizing_foot_side, recommended_width_category,
-- measurement_source, algorithm_version, shoe_category and
-- size_recommendation_reason — and not one of the six below. No file in this
-- repository drops them, so the drift came from outside the migration
-- lineage; the baseline migration stays the source of truth and this file
-- brings the live table back to it.
--
-- Additive and idempotent: ADD COLUMN IF NOT EXISTS, no data change, no
-- policy, grant, index or trigger touched. Re-running it is a no-op.
--
-- THE SAME SAVE ALSO FAILED ON A CHECK CONSTRAINT (found while verifying this
-- file on 2026-11-19). The live table carried
--   paper_size_used = ANY (ARRAY['a4','letter'])
-- but the card scan writes 'card' (the ID-1 reference card, commit 668f352) and
-- the live AR and v2 paths write 'ar' — so every one of those inserts died on
-- 23514 before the column bug above was even reachable. Both values are part
-- of the app's documented contract (FootMeasurement.paperSizeUsed: 'ar', 'a4',
-- 'letter' or 'card'), so the constraint is replaced with the full set instead
-- of being dropped: the column still refuses a typo, it just admits every
-- value the app can legitimately send.

begin;

alter table public.foot_measurements
  add column if not exists length_confidence_left double precision,
  add column if not exists length_confidence_right double precision,
  add column if not exists overall_confidence_score double precision,
  add column if not exists confidence_level text,
  add column if not exists raw_sample_count integer,
  add column if not exists final_sample_count integer;

comment on column public.foot_measurements.length_confidence_left is
  'Left-foot length sample spread (IQR) from the live AR scan.';
comment on column public.foot_measurements.length_confidence_right is
  'Right-foot length sample spread (IQR) from the live AR scan.';
comment on column public.foot_measurements.overall_confidence_score is
  'Aggregate scan confidence, 0.0–1.0.';
comment on column public.foot_measurements.confidence_level is
  'Confidence bucket: high, medium or low.';
comment on column public.foot_measurements.raw_sample_count is
  'Samples collected before filtering.';
comment on column public.foot_measurements.final_sample_count is
  'Samples kept after filtering.';

-- The paper_size_used CHECK admitted only 'a4' and 'letter'; the card scan
-- sends 'card' and the AR paths send 'ar'. Replace it with the full contract.
-- (No row can be holding a value outside the old set, so this cannot fail on
-- existing data.)
alter table public.foot_measurements
  drop constraint if exists foot_measurements_paper_size_used_check;

alter table public.foot_measurements
  add constraint foot_measurements_paper_size_used_check
  check (paper_size_used in ('ar', 'a4', 'letter', 'card'));

comment on column public.foot_measurements.paper_size_used is
  'Reference used for the scan: ar (live ARCore), a4, letter, or card (ID-1 85.60 x 53.98 mm).';

-- PostgREST caches the column list; new columns are picked up by its DDL
-- watcher, and this makes the reload explicit so a save attempted seconds
-- after the apply cannot still see the old cache.
notify pgrst, 'reload schema';

commit;
