-- ══════════════════════════════════════════════════════════════════
-- Migration: Audit initial application submissions (T3 follow-up)
-- Date: 2026-09-03
--
-- Gap found during live verification: this project has NO trigger that
-- creates a profiles row on auth signup (confirmed: grep of schema +
-- migrations, and a live signup+submit test left the audit log without
-- a 'submitted' row). The app's first-time submit therefore goes
-- through completeSellerApplication's upsert, which takes the
-- INSERT ... ON CONFLICT DO UPDATE INSERT branch, inserting the row
-- directly with seller_status='pending' — so the AFTER UPDATE OF
-- seller_status trigger (20260903010000) never fires for it.
--
-- FIX: an AFTER INSERT trigger that logs the initial submission. The
-- WHEN clause restricts it to rows born with seller_status='pending',
-- so customer signups and the getProfile fallback ('none') are never
-- logged. Re-submissions of an existing (rejected) row go through the
-- UPDATE branch and are already covered by the 20260903010000 trigger.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.log_seller_application_submission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- A profile born in 'pending' IS a submitted seller application.
    -- previous_status is NULL (there was no prior state).
    IF NEW.seller_status = 'pending' THEN
        INSERT INTO public.seller_application_audit_log (
            profile_id, actor_id, action,
            previous_status, new_status, notes
        ) VALUES (
            NEW.id,
            auth.uid(),
            'submitted',
            NULL,
            NEW.seller_status,
            NULL
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_seller_application_submission ON public.profiles;
CREATE TRIGGER trg_log_seller_application_submission
    AFTER INSERT ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.log_seller_application_submission();

COMMENT ON FUNCTION public.log_seller_application_submission IS
    'AFTER INSERT ON profiles WHEN new seller_status = pending: logs the '
    'initial application submission to seller_application_audit_log. '
    'Companion to log_seller_application_status_change (AFTER UPDATE). '
    'SECURITY DEFINER so the insert bypasses RLS/grants — the trigger is '
    'the only write path to the audit log.';