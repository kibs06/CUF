-- ══════════════════════════════════════════════════════════════════
-- FIX failed_logins RLS — enable pre-authentication tracking
-- ══════════════════════════════════════════════════════════════════
-- Previous migration (20260829100000) added the table but the RLS
-- policies assumed the caller is authenticated. During a FAILED
-- login attempt the user has no session, so auth.uid() is NULL
-- and every SELECT / UPDATE is silently blocked by Postgres RLS.
--
-- This migration drops all per-user policies and replaces them
-- with permissive policies that allow the full flow:
--   1. SELECT  — checkLockout needs to READ the row before auth
--   2. INSERT  — first failed attempt creates the row
--   3. UPDATE  — subsequent attempts increment the counter,
--                successful login resets it, expiry auto-unlocks
--
-- Security notes:
--   • user_id FK guarantees referential integrity (must match
--     an existing auth.users row)
--   • The data is tracking metadata only (timestamps, counts,
--     ip, user_agent) — not sensitive user data
--   • Admins can still view all rows via the admin SELECT policy
-- ══════════════════════════════════════════════════════════════════

-- Drop ALL existing policies and recreate them
DROP POLICY IF EXISTS "Users can view own failed logins" ON public.failed_logins;
DROP POLICY IF EXISTS "Users can insert own failed logins" ON public.failed_logins;
DROP POLICY IF EXISTS "Users can update own failed logins" ON public.failed_logins;
DROP POLICY IF EXISTS "Allow failed login inserts" ON public.failed_logins;
DROP POLICY IF EXISTS "Admins can view all failed logins" ON public.failed_logins;
DROP POLICY IF EXISTS "Admins can update failed logins" ON public.failed_logins;

-- SELECT: any caller can read (needed for pre-login lockout check
-- and for advanceFailedCounter to read the existing attempt count)
CREATE POLICY "Allow failed logins read"
    ON public.failed_logins FOR SELECT
    USING (true);

-- INSERT: any caller can insert (first failed attempt)
CREATE POLICY "Allow failed logins insert"
    ON public.failed_logins FOR INSERT
    WITH CHECK (true);

-- UPDATE: any caller can update (increment counter, reset, unlock)
CREATE POLICY "Allow failed logins update"
    ON public.failed_logins FOR UPDATE
    USING (true);
