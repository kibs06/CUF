-- ══════════════════════════════════════════════════════════════════
-- Migration: business-document resubmission tracking
-- Date: 2026-11-17
--
-- WHY THIS CHANGE:
--   A rejected Tier 2 submission is not the end of the story — the seller
--   can fix the paperwork and submit again, and `submitBusinessVerification`
--   does exactly that (status back to 'pending'). But the row then looks
--   IDENTICAL to a first submission: `verification_status = 'pending'`, and
--   the admin queue orders by `created_at`, which never moved. So a seller
--   who resubmitted after a rejection sank to the bottom of the queue
--   behind brand-new submissions, and the reviewer had no way to tell that
--   this row was a second attempt at a request they had already turned
--   down. That is how a verification queue stalls.
--
--   This file records the event on the row itself:
--     • `resubmitted_at`    — when the seller re-submitted after a
--                             rejection. Stamped by the transition
--                             'rejected' → 'pending', nothing else.
--     • `resubmission_count` — how many times, so a third attempt is not
--                             mistaken for the first retry.
--
--   It is deliberately a column and not a notification row: neither admin
--   console has a notification feed (the Flutter console's bell belongs to
--   the seller shell, and the React portal reads no user feed at all), so a
--   `notifications` row for admins would be written into a table no admin
--   surface renders. The durable signal is the row these screens already
--   read, and both consoles show it: the Flutter dashboard gets an alert
--   count and the Business Docs queue lifts resubmitted rows to the top
--   with a "Resubmitted" chip. Because the flag lives until an admin makes
--   a new verdict, the alert cannot be missed by being offline at the
--   wrong moment — the state IS the notification, not a transient message
--   about it.
--
--   Additive: two nullable/defaulted columns and one BEFORE trigger. No
--   policy, grant or existing row changes.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. COLUMNS
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_business_docs
    ADD COLUMN IF NOT EXISTS resubmitted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE public.seller_business_docs
    ADD COLUMN IF NOT EXISTS resubmission_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.seller_business_docs.resubmitted_at IS
    'When the seller re-submitted after a rejection (verification_status rejected → pending). NULL for a first submission and for rows that were never rejected. Deliberately NOT cleared by a later verdict: it is the audit trail of the attempt the admin is reviewing.';

COMMENT ON COLUMN public.seller_business_docs.resubmission_count IS
    'How many times this seller has re-submitted after a rejection. Stays at 0 for a first submission.';

-- The admin alert counts pending rows that carry a resubmission stamp;
-- keep that lookup off a sequential scan.
CREATE INDEX IF NOT EXISTS idx_seller_business_docs_resubmitted
    ON public.seller_business_docs (resubmitted_at)
    WHERE verification_status = 'pending';

-- ────────────────────────────────────────────────────────────────
-- 2. STAMP THE TRANSITION
--    BEFORE UPDATE so the stamp travels in the same row write the seller
--    (or the app's upsert) already performs — no second statement to lose.
--
--    Only 'rejected' → 'pending' counts. A re-submit that never followed a
--    rejection (status was already 'pending', e.g. the seller replaced one
--    file) leaves the stamp and the counter alone: the admin has not
--    rejected this attempt yet, so there is nothing to re-open.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.track_business_docs_resubmission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.verification_status = 'rejected'
       AND NEW.verification_status = 'pending' THEN
        NEW.resubmitted_at := timezone('utc'::text, now());
        NEW.resubmission_count := COALESCE(OLD.resubmission_count, 0) + 1;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.track_business_docs_resubmission() IS
    'Stamps resubmitted_at and increments resubmission_count on the rejected → pending transition, so the admin queue can lift and flag a second attempt instead of burying it.';

DROP TRIGGER IF EXISTS trg_track_business_docs_resubmission
    ON public.seller_business_docs;
CREATE TRIGGER trg_track_business_docs_resubmission
    BEFORE UPDATE OF verification_status ON public.seller_business_docs
    FOR EACH ROW EXECUTE FUNCTION public.track_business_docs_resubmission();

-- Trigger functions are never called through PostgREST.
REVOKE EXECUTE ON FUNCTION public.track_business_docs_resubmission() FROM PUBLIC;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Columns and the trigger:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'seller_business_docs'
--     AND column_name IN ('resubmitted_at', 'resubmission_count');
-- SELECT tgname FROM pg_trigger
--   WHERE tgname = 'trg_track_business_docs_resubmission';
--
-- -- The admin alert's count (the query the dashboard runs):
-- SELECT count(*) FROM public.seller_business_docs
--   WHERE verification_status = 'pending' AND resubmitted_at IS NOT NULL;
--
-- -- Dry run on one seller (rollback-safe):
-- -- BEGIN;
-- --   UPDATE public.seller_business_docs SET verification_status = 'rejected'
-- --     WHERE profile_id = '<seller uuid>';
-- --   UPDATE public.seller_business_docs SET verification_status = 'pending'
-- --     WHERE profile_id = '<seller uuid>';
-- --   SELECT resubmitted_at, resubmission_count
-- --     FROM public.seller_business_docs WHERE profile_id = '<seller uuid>';
-- --   -- expect a timestamp and 1 (or the previous count + 1)
-- -- ROLLBACK;
--
-- ══════════════════════════════════════════════════════════════════
-- ROLLBACK / UNDO (manual — this repository does not auto-revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS trg_track_business_docs_resubmission
--   ON public.seller_business_docs;
-- DROP FUNCTION IF EXISTS public.track_business_docs_resubmission();
-- ALTER TABLE public.seller_business_docs
--   DROP COLUMN IF EXISTS resubmission_count,
--   DROP COLUMN IF EXISTS resubmitted_at;
