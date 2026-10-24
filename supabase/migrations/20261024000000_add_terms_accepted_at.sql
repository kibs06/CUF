-- ══════════════════════════════════════════════════════════════════
-- Migration: first-time Terms & Privacy acceptance timestamp
-- Date: 2026-10-24
--
-- Adds public.profiles.terms_accepted_at (TIMESTAMPTZ NULL): the
-- server-side source of truth for the one-time Terms & Privacy gate
-- AuthGate shows first-time social (Google/Facebook) customers.
-- NULL = never accepted (gate shows); set = accepted (gate skips).
--
-- Email/password registrants accept via the register-screen checkbox and
-- sellers via the application flow, so in practice only social accounts
-- arrive with NULL — but the gate also checks the session provider, so
-- a NULL here alone never misfires.
--
-- No RLS or trigger change is needed:
--   - "Users can update their own profile" (FOR UPDATE USING
--     auth.uid() = id) already permits the owner to write this column.
--   - guard_profiles_sensitive_columns() (20260903000000) does not list
--     this column, so owners can stamp only their own acceptance while
--     role / seller_status / suspended* / application-record columns
--     stay locked. Verified against the live policies before applying.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.terms_accepted_at IS
  'First-time Terms & Privacy acceptance: NULL until a first-time social customer taps "I have read and I agree", then the acceptance timestamp forever. Server-side source of truth for AuthGate''s once-ever terms gate.';
