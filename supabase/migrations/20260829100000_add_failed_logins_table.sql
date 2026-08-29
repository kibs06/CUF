-- ══════════════════════════════════════════════════════════════════
-- FAILED LOGINS TABLE — brute-force / intrusion detection
-- ══════════════════════════════════════════════════════════════════
-- Tracks failed login attempts per account for brute-force detection.
-- Lockout triggers after 5 consecutive failed attempts.
--
--  ✅ user_id → profiles (auth user)
--  ✅ ip_address + user_agent for admin forensics
--  ✅ locked_until for lockout window
--  ✅ status: 'active' | 'locked' | 'expired'
--  ✅ Single row per user (upsert on each attempt)
-- ══════════════════════════════════════════════════════════════════

-- ── Table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.failed_logins (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ip_address      TEXT,
    user_agent      TEXT,
    failed_at       TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    locked_until    TIMESTAMPTZ,
    status          text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'locked', 'expired'))
);

-- Unique constraint: one active/locked row per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_active_failed ON public.failed_logins(user_id) WHERE status IN ('active', 'locked');

-- Index for admin queries: find locked-out users
CREATE INDEX IF NOT EXISTS idx_failed_logins_status ON public.failed_logins(status);
CREATE INDEX IF NOT EXISTS idx_failed_logins_user_id ON public.failed_logins(user_id);
CREATE INDEX IF NOT EXISTS idx_failed_logins_locked_until ON public.failed_logins(locked_until);

-- RLS: users can see their own row, admins can see all
ALTER TABLE public.failed_logins ENABLE ROW LEVEL SECURITY;

-- Users can view their own failed login row
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own failed logins' AND tablename = 'failed_logins') THEN
        CREATE POLICY "Users can view own failed logins"
            ON public.failed_logins FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can insert their own failed login row
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own failed logins' AND tablename = 'failed_logins') THEN
        CREATE POLICY "Users can insert own failed logins"
            ON public.failed_logins FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Admins can view all failed logins
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can view all failed logins' AND tablename = 'failed_logins') THEN
        CREATE POLICY "Admins can view all failed logins"
            ON public.failed_logins FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can update failed logins (e.g. clear lockout, change status)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can update failed logins' AND tablename = 'failed_logins') THEN
        CREATE POLICY "Admins can update failed logins"
            ON public.failed_logins FOR UPDATE
            USING (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;