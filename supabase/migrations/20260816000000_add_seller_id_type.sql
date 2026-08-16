-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller identity — government ID type selection
-- Date: 2026-08-16
--
-- WHY THIS CHANGE:
--   The Tier 1 seller application (20260812000000) collects a government
--   ID photo + selfie but not WHICH government ID the applicant used.
--   Admins reviewing an application now have to guess the document type
--   from the photo. The application flow now asks the seller to pick the
--   ID type first (AppConstants.govIdTypes: PhilID, passport, driver's
--   license, UMID/SSS, GSIS eCard, PRC, Postal, Voter's, Senior Citizen,
--   PWD, TIN, NBI Clearance), and that selection is stored here so admin
--   review shows it next to the document.
--
-- Additive + nullable: pre-migration applications and customers are
-- unaffected (legacy rows simply have no id_type).
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS id_type TEXT;

COMMENT ON COLUMN public.profiles.id_type IS
    'Tier 1: the government ID type the applicant selected (one of AppConstants.govIdTypes values, e.g. philid, passport, drivers_license). NULL for legacy applications submitted before this column existed.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--     AND column_name = 'id_type';
