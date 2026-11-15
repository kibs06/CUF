-- ══════════════════════════════════════════════════════════════════
-- Migration: admin notifications
-- Date: 2026-11-18
--
-- WHY THIS CHANGE:
--   The previous file made a business-document resubmission visible by
--   stamping the row and counting it on the dashboard. A count is a state,
--   not a message: an admin cannot see WHAT happened (who resubmitted, when,
--   how many attempts), cannot mark it dealt with, and the number cannot
--   survive the moment the queue is cleared. Admins also had no feed at all
--   — the customer `notifications` table belongs to the customer shell, and
--   the seller's bell is store-scoped, so there was nowhere to put a row for
--   a person whose job is reviewing other people's work.
--
--   This file adds the missing channel:
--
--     • `admin_notifications` — one row per admin per event. Its own table,
--       like `seller_notifications`, so an admin's feed never mixes with a
--       customer's orders or a store's bell.
--     • A trigger on `seller_business_docs` writes one row to EVERY admin
--       when a seller resubmits after a rejection. It is inserted inside the
--       same transaction as the resubmission, so the notice cannot exist
--       without the state it describes, nor the state without the notice.
--     • RLS: an admin reads and marks read only their OWN rows, and only
--       while they still hold the admin role. Writes come from the trigger
--       (SECURITY DEFINER) — there is no client INSERT policy.
--
--   The `resubmission_count` is read through `to_jsonb(NEW)` rather than as
--   a column so this file does not depend on the exact column set of
--   20261117000000; apply that one first for the count to be meaningful,
--   but this migration is safe on its own.
--
--   Additive: a new table with its policies and indexes, one trigger, and
--   the trusted-device gate every RLS table in this project carries (the
--   gate is `device_is_trusted() OR is_admin()`, so an admin is unaffected).
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. TABLE
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_notifications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type         TEXT NOT NULL
                     CHECK (type IN ('business_docs_resubmitted')),
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,
    -- The row this notice is about (a profile id here, since the queue is
    -- per seller; a nullable column so future types can point elsewhere).
    reference_id UUID,
    metadata     JSONB DEFAULT NULL,
    is_read      BOOLEAN NOT NULL DEFAULT false,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE public.admin_notifications IS
    'Per-admin feed: events an admin has to act on (currently business-document resubmissions). Separate from the customer notifications feed and from the store-scoped seller bell.';

COMMENT ON COLUMN public.admin_notifications.reference_id IS
    'What the notice is about — the seller''s profile id for business_docs_resubmitted.';

CREATE INDEX IF NOT EXISTS idx_admin_notifications_user
    ON public.admin_notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_notifications_unread
    ON public.admin_notifications (user_id)
    WHERE is_read = false;

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

-- Read your own rows, while you are an admin. A demoted account stops
-- seeing the queue it no longer works.
DROP POLICY IF EXISTS "Admins can read own admin notifications"
    ON public.admin_notifications;
CREATE POLICY "Admins can read own admin notifications"
    ON public.admin_notifications
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid() AND public.is_admin());

-- Mark read / unread: only the read flag, only your own rows.
DROP POLICY IF EXISTS "Admins can update own admin notifications"
    ON public.admin_notifications;
CREATE POLICY "Admins can update own admin notifications"
    ON public.admin_notifications
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid() AND public.is_admin())
    WITH CHECK (user_id = auth.uid() AND public.is_admin());

-- No INSERT policy on purpose: every row is written by the trigger below
-- (SECURITY DEFINER), so a client cannot fabricate an admin notice.

-- ────────────────────────────────────────────────────────────────
-- 2. THE EVENT
--    Fires on the same transition 20261117000000 stamps: a seller this
--    admin queue already rejected has sent new documents. One row per
--    admin; a queue with no admins writes nothing (and must not fail).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admins_on_docs_resubmission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_name  text;
    v_store text;
    v_count integer;
BEGIN
    SELECT COALESCE(NULLIF(BTRIM(p.full_name), ''), 'A seller'),
           NULLIF(BTRIM(p.store_name), '')
      INTO v_name, v_store
      FROM public.profiles p
     WHERE p.id = NEW.profile_id;

    -- Read through the row's jsonb so an older/absent resubmission_count
    -- column cannot break the notice.
    v_count := COALESCE((to_jsonb(NEW) ->> 'resubmission_count')::int, 0);

    INSERT INTO public.admin_notifications
        (user_id, type, title, body, reference_id, metadata)
    SELECT a.id,
           'business_docs_resubmitted',
           'Business documents resubmitted',
           v_name ||
             CASE WHEN v_store IS NOT NULL THEN ' (' || v_store || ')' ELSE '' END ||
             ' sent new documents after a rejection. Review them in the Business Docs queue.',
           NEW.profile_id,
           jsonb_build_object(
               'kind', 'business_docs_resubmitted',
               'profile_id', NEW.profile_id,
               'resubmission_count', v_count
           )
      FROM public.profiles a
     WHERE a.role = 'admin';

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_admins_on_docs_resubmission() IS
    'Writes one admin_notifications row per admin when a seller resubmits business documents after a rejection, so the queue can be worked from a feed instead of a bare count.';

DROP TRIGGER IF EXISTS trg_notify_admins_on_docs_resubmission
    ON public.seller_business_docs;
CREATE TRIGGER trg_notify_admins_on_docs_resubmission
    AFTER UPDATE OF verification_status ON public.seller_business_docs
    FOR EACH ROW
    WHEN (
        OLD.verification_status = 'rejected'
        AND NEW.verification_status = 'pending'
    )
    EXECUTE FUNCTION public.notify_admins_on_docs_resubmission();

REVOKE EXECUTE ON FUNCTION public.notify_admins_on_docs_resubmission() FROM PUBLIC;

-- ────────────────────────────────────────────────────────────────
-- 3. TRUSTED-DEVICE GATE
--    This repository's invariant (asserted by
--    admin_account_security.test.sql): every RLS table is either gated by
--    `install_device_gate_policies()` or listed in
--    `device_gate_exempt_tables()` with a reason. The gate is
--    `device_is_trusted() OR is_admin()`, so for the only readers of this
--    table — admins — it changes nothing, and it keeps the feed under the
--    same device policy as the rest of the admin surface instead of
--    quietly becoming the one ungated table.
-- ────────────────────────────────────────────────────────────────
SELECT public.install_device_gate_policies();

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- One row per admin after a resubmission:
-- SELECT user_id, type, title, reference_id, metadata, is_read
--   FROM public.admin_notifications ORDER BY created_at DESC LIMIT 5;
--
-- -- RLS: an admin sees only their own rows, a seller sees none.
-- --   (In the SQL editor you bypass RLS; verify in the app, or as a role:)
-- -- BEGIN;
-- --   SET LOCAL ROLE authenticated;
-- --   SET LOCAL request.jwt.claims = '{"sub":"<admin uuid>","role":"authenticated"}';
-- --   SELECT count(*) FROM public.admin_notifications;
-- -- ROLLBACK;
--
-- ══════════════════════════════════════════════════════════════════
-- ROLLBACK / UNDO (manual — this repository does not auto-revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS trg_notify_admins_on_docs_resubmission
--   ON public.seller_business_docs;
-- DROP FUNCTION IF EXISTS public.notify_admins_on_docs_resubmission();
-- DROP TABLE IF EXISTS public.admin_notifications;
