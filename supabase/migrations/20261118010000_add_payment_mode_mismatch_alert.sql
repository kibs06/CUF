-- ══════════════════════════════════════════════════════════════════
-- Migration: payment-mode-mismatch alerts reach an admin
-- Date: 2026-11-18
--
-- WHY THIS CHANGE:
--   The PayMongo mode guards (shipped 2026-11-17) stop the wrong kind of
--   money from moving, and they write an audit row to
--   `payment_webhook_events` — a table with NO read policy, so an admin
--   never sees it in the portal. A guard that trips is therefore silent:
--   checkout starts returning 503, or a real live payment is left
--   unconfirmed for retry, and nobody is told until a customer complains.
--
--   `admin_notifications` (20261118000000) is exactly the channel for this
--   — per-admin rows, admin-only read RLS, already surfaced in the portal
--   bell. Two things were missing:
--
--     • its `type` CHECK allowed only 'business_docs_resubmitted';
--     • there was no writer a server-side caller could use — the table
--       deliberately has NO INSERT policy, because the only writer so far
--       was a SECURITY DEFINER trigger.
--
--   This file adds 'payment_mode_mismatch' to the CHECK and one narrow
--   SECURITY DEFINER function the Edge Functions call with the service
--   role. The admin-only READ policies are untouched, and the table still
--   has no client INSERT path: a normal authenticated user (admin or not)
--   cannot fabricate a notice.
--
--   The Edge Functions treat the call as best-effort: the insert is
--   wrapped in a try/catch and a failure is logged and swallowed, so the
--   webhook's HTTP outcome (500 retry / 200 acknowledge) is unchanged and
--   checkout still returns its 503. That matters while this migration is
--   unapplied — a rejected insert is expected and harmless, never fatal.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. TYPE CHECK — idempotent drop + re-add
--    The original constraint was declared inline on the column, so its
--    generated name is assumed rather than guaranteed. The DO block drops
--    ANY check constraint on this table that mentions the old type, then
--    the named constraint below is added once. Safe to re-run.
-- ────────────────────────────────────────────────────────────────
DO $$
DECLARE
    c record;
BEGIN
    FOR c IN
        SELECT conname
          FROM pg_constraint
         WHERE conrelid = 'public.admin_notifications'::regclass
           AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%business_docs_resubmitted%'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.admin_notifications DROP CONSTRAINT %I',
            c.conname
        );
    END LOOP;
END $$;

ALTER TABLE public.admin_notifications
    DROP CONSTRAINT IF EXISTS admin_notifications_type_check;

ALTER TABLE public.admin_notifications
    ADD CONSTRAINT admin_notifications_type_check
    CHECK (type IN ('business_docs_resubmitted', 'payment_mode_mismatch'));

-- ────────────────────────────────────────────────────────────────
-- 2. WRITER — one row per admin per guard trip
--    SECURITY DEFINER so it can insert into a table that has no INSERT
--    policy. EXECUTE is granted to service_role ONLY: the Edge Functions
--    (which hold the service key) are the only callers, and a browser
--    holding an admin session cannot call it.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admins_payment_mode_mismatch(
    p_source     text,
    p_title      text,
    p_body       text,
    p_metadata   jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count integer;
BEGIN
    INSERT INTO public.admin_notifications
        (user_id, type, title, body, metadata)
    SELECT a.id,
           'payment_mode_mismatch',
           p_title,
           p_body,
           COALESCE(p_metadata, '{}'::jsonb)
                      || jsonb_build_object('kind', 'payment_mode_mismatch',
                                            'source', p_source)
      FROM public.profiles a
     WHERE a.role = 'admin';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.notify_admins_payment_mode_mismatch(text, text, text, jsonb) IS
    'Writes one admin_notifications row per admin when a PayMongo mode guard trips, so a blocked or unconfirmed payment surfaces in the admin bell instead of sitting silently in payment_webhook_events. Service-role only; best-effort from the Edge Functions.';

REVOKE ALL ON FUNCTION public.notify_admins_payment_mode_mismatch(text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_admins_payment_mode_mismatch(text, text, text, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.notify_admins_payment_mode_mismatch(text, text, text, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.notify_admins_payment_mode_mismatch(text, text, text, jsonb) TO service_role;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- The constraint now allows both types:
-- SELECT pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid = 'public.admin_notifications'::regclass AND contype = 'c';
--
-- -- Only the service role may write:
-- SELECT has_function_privilege('authenticated',
--          'public.notify_admins_payment_mode_mismatch(text,text,text,jsonb)', 'EXECUTE');  -- false
-- SELECT has_function_privilege('service_role',
--          'public.notify_admins_payment_mode_mismatch(text,text,text,jsonb)', 'EXECUTE');  -- true
--
-- -- One row per admin after a guard trip:
-- SELECT user_id, type, title, is_read, metadata
--   FROM public.admin_notifications
--  WHERE type = 'payment_mode_mismatch'
--  ORDER BY created_at DESC LIMIT 5;
--
-- ══════════════════════════════════════════════════════════════════
-- ROLLBACK / UNDO (manual — this repository does not auto-revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.notify_admins_payment_mode_mismatch(text, text, text, jsonb);
-- ALTER TABLE public.admin_notifications DROP CONSTRAINT IF EXISTS admin_notifications_type_check;
-- ALTER TABLE public.admin_notifications
--   ADD CONSTRAINT admin_notifications_type_check
--   CHECK (type IN ('business_docs_resubmitted'));
