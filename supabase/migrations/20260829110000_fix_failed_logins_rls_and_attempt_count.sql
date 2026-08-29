-- ══════════════════════════════════════════════════════════════════
-- FIX failed_logins: add attempt_count column + fix RLS policies
-- ══════════════════════════════════════════════════════════════════
-- The original migration had two critical issues:
--  1. Missing `attempt_count` column (needed by advanceFailedCounter)
--  2. RLS INSERT policy uses auth.uid() which is NULL when the user
--     is NOT authenticated (i.e. after a failed login attempt).
--     This silently blocks every failed-login write.
--  3. No UPDATE policy for non-admins.
-- ══════════════════════════════════════════════════════════════════

-- Add the missing attempt_count column
ALTER TABLE public.failed_logins
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0;

-- Drop the overly-restrictive INSERT policy that requires auth.uid()
DROP POLICY IF EXISTS "Users can insert own failed logins" ON public.failed_logins;

-- New INSERT policy: allow any authenticated OR unauthenticated insert.
-- The table only stores attempt metadata (ip, user_agent, timestamps),
-- not sensitive data. The user_id FK guarantees referential integrity.
CREATE POLICY "Allow failed login inserts"
    ON public.failed_logins FOR INSERT
    WITH CHECK (true);

-- Add UPDATE policy for authenticated users on their own row
-- (needed by advanceFailedCounter and resetFailedCounter)
DROP POLICY IF EXISTS "Users can update own failed logins" ON public.failed_logins;

CREATE POLICY "Users can update own failed logins"
    ON public.failed_logins FOR UPDATE
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );
