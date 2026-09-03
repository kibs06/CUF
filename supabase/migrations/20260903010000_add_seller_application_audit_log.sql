-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller application audit log (Threat T3 — no audit trail)
-- Date: 2026-09-03
--
-- Problem: nothing records who changed an application's status, when,
-- or from what to what. Approve/reject are raw UPDATEs on profiles
-- from the admin portal (useSellerApplications.js / useDashboard.js),
-- and the applicant's own submit writes seller_status='pending'.
-- Confirmed absent in schema + migrations as of 2026-09-03.
--
-- FIX: an immutable audit log written ONLY by a database trigger on
-- profiles.seller_status changes. A trigger (not app-level logging)
-- cannot be bypassed by any client calling the API directly.
--
-- Access model:
--   • SELECT — admins only (RLS policy using public.is_admin()).
--   • INSERT/UPDATE/DELETE/TRUNCATE — revoked from every role,
--     including service_role, so the ONLY writer is the SECURITY
--     DEFINER trigger function (runs as the table owner).
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_application_audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The profile whose application status changed (the "application
    -- record" in this schema is the profiles row; FK so a deleted
    -- account takes its history with it).
    profile_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    -- The user who performed the change (admin, or the applicant
    -- himself on initial submit). NULL never occurs through the
    -- trigger — auth.uid() is set for every client statement.
    actor_id        UUID NOT NULL,
    -- submitted | approved | rejected | status_changed
    action          TEXT NOT NULL,
    previous_status TEXT,
    new_status      TEXT NOT NULL,
    -- Reviewer note captured from profiles.rejection_reason on reject
    -- (the admin portal already writes it — no UI change needed).
    notes           TEXT,
    created_at      TIMESTAMP WITH TIME ZONE
                        DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE public.seller_application_audit_log IS
    'Immutable audit trail of seller application status changes. '
    'Writeable ONLY by the log_seller_application_status_change trigger — '
    'all direct INSERT/UPDATE/DELETE/TRUNCATE grants are revoked, including '
    'from service_role.';

CREATE INDEX IF NOT EXISTS seller_application_audit_log_profile_idx
    ON public.seller_application_audit_log (profile_id, created_at DESC);

-- ────────────────────────────────────────────────────────────────
-- RLS — admin read-only; no write path exists for any role
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_application_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read application audit log"
    ON public.seller_application_audit_log;
CREATE POLICY "Admins can read application audit log"
    ON public.seller_application_audit_log FOR SELECT
    USING (public.is_admin());

-- Belt-and-suspenders at the grant level: even service_role (which
-- bypasses RLS) must not be able to write — only the owner-running
-- trigger may. Admins keep SELECT through the policy above.
REVOKE ALL ON public.seller_application_audit_log FROM PUBLIC;
GRANT  SELECT ON public.seller_application_audit_log TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- Trigger — the single write path
-- ────────────────────────────────────────────────────────────────
-- SECURITY DEFINER: the trigger fires during a client UPDATE on
-- profiles; the INSERT it performs must run as the table owner so it
-- is not blocked by RLS / the revoked grants. search_path pinned.
-- auth.uid() is schema-qualified so it resolves regardless of
-- search_path and always returns the real calling user.
CREATE OR REPLACE FUNCTION public.log_seller_application_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action text;
BEGIN
    -- Only act when the status actually changed.
    IF NEW.seller_status IS DISTINCT FROM OLD.seller_status THEN
        v_action := CASE
            WHEN OLD.seller_status = 'none' AND NEW.seller_status = 'pending'
                THEN 'submitted'
            WHEN NEW.seller_status = 'approved' THEN 'approved'
            WHEN NEW.seller_status = 'rejected' THEN 'rejected'
            ELSE 'status_changed'
        END;

        INSERT INTO public.seller_application_audit_log (
            profile_id, actor_id, action,
            previous_status, new_status, notes
        ) VALUES (
            NEW.id,
            auth.uid(),
            v_action,
            OLD.seller_status,
            NEW.seller_status,
            -- Capture the admin's reviewer note only on rejection
            -- (the portal writes profiles.rejection_reason in the
            -- same UPDATE); NULL everywhere else.
            CASE WHEN NEW.seller_status = 'rejected'
                 THEN NEW.rejection_reason ELSE NULL END
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_seller_application_status_change ON public.profiles;
CREATE TRIGGER trg_log_seller_application_status_change
    AFTER UPDATE OF seller_status ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.log_seller_application_status_change();

COMMENT ON FUNCTION public.log_seller_application_status_change IS
    'AFTER UPDATE OF seller_status ON profiles: appends one immutable row to '
    'seller_application_audit_log (actor, action, previous/new status, reviewer '
    'notes on reject). SECURITY DEFINER so the insert bypasses RLS/grants — '
    'the trigger is the only write path to the audit log.';