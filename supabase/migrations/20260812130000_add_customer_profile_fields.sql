-- ══════════════════════════════════════════════════════════════════
-- Customer profile + foot-profile snapshot fields
-- ══════════════════════════════════════════════════════════════════
-- Adds the fields collected at customer sign-up (birthday, gender) and the
-- foot-profile snapshot that the rest of the app can read cheaply
-- (checkout, size recommendations, reminder banners).
--
-- Full scan fidelity is NOT stored here: the `foot_measurements` table
-- (20260730100000_add_foot_measurements.sql) keeps the complete per-foot
-- AR/paper scan result. These columns are a denormalized convenience
-- snapshot — effective size + source — kept in sync by the app whenever a
-- scan is saved or the user picks a manual size.
--
--   foot_profile_source: 'ar_scan' | 'manual' | 'skipped'
--     - 'ar_scan'  → measured via the live AR tap-to-measure flow
--     - 'manual'   → lightweight size+width picker (signup fallback) OR a
--                    paper-based camera scan (non-AR, lower confidence tier)
--     - 'skipped'  → user explicitly skipped during onboarding
--     NULL         → never touched (pre-feature accounts) — treated the same
--                    as 'skipped' by the reminder banner.
--
--   foot_size_ph: effective EU size as a number (e.g. 40.5). For scanned
--                 profiles this mirrors foot_measurements.recommended_eu_size
--                 (or user_adjusted_eu_size when adjusted).
--   foot_width:   'Narrow' | 'Regular' | 'Wide' — only set by the manual
--                 picker; scans keep the measured width in foot_measurements.
--   foot_profile_updated_at: last time the snapshot changed.
--
-- RLS is unaffected: profiles is already covered by the existing
-- "Users can update their own profile" policy.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS birthday             DATE,
  ADD COLUMN IF NOT EXISTS gender               TEXT,
  ADD COLUMN IF NOT EXISTS foot_size_ph         NUMERIC,
  ADD COLUMN IF NOT EXISTS foot_width           TEXT,
  ADD COLUMN IF NOT EXISTS foot_profile_source  TEXT
      CHECK (foot_profile_source IN ('ar_scan', 'manual', 'skipped')),
  ADD COLUMN IF NOT EXISTS foot_profile_updated_at TIMESTAMP WITH TIME ZONE;
