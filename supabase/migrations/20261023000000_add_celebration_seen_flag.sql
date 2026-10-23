-- ══════════════════════════════════════════════════════════════════
-- Migration: once-only seller approval celebration flag
-- Date: 2026-10-23
--
-- Adds public.profiles.has_seen_approval_celebration (BOOLEAN NOT NULL
-- DEFAULT FALSE): the server-side source of truth for the one-time
-- "You're now part of the CUFMAI family!" welcome.
--
-- Why this column exists: AuthGate previously persisted the "seen" flag
-- only in device-local SharedPreferences
-- (seller_celebration_seen_v1), so a reinstall, app-data clear, or a
-- second device re-showed the celebration. This flag survives all of
-- those — the client treats prefs as a write-through cache and the
-- server value as the authority.
--
-- No RLS or trigger change is needed:
--   - "Users can update their own profile" (FOR UPDATE USING
--     auth.uid() = id) already permits the owner to write this column.
--   - guard_profiles_sensitive_columns() (20260903000000) does not list
--     this column, so owners can flip only this flag while role /
--     seller_status / suspended* / application-record columns stay
--     locked. Verified against the live policies before applying.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS has_seen_approval_celebration BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.has_seen_approval_celebration IS
  'Once-only seller approval celebration: false until the approved seller taps "Go to dashboard", then true forever. Server-side source of truth; device prefs is only a write-through cache.';
