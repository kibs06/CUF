-- ══════════════════════════════════════════════════════════════════
-- Migration: a model reaches `active` only through the server validator
-- Date: 2026-09-28
-- Roadmap: docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md V2.4
-- Design:  docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md §2.5.4
--
-- ── Why this exists ───────────────────────────────────────────────
-- V2.4 is the server-side validator (`validate-shoe-model`), and §2.5.4
-- is explicit that client-side validation is *not* a security boundary:
-- it exists to give sellers fast feedback.
--
-- The Edge Function alone does not change that. The `product_models`
-- policies from 20260927180000 let a seller INSERT or UPDATE their own
-- rows with any status they like — so before this file, "the model is
-- validated before it goes live" was a claim about the *app's* behaviour,
-- and anyone with a seller token and curl could publish an unvalidated
-- mesh by writing `status='active'` directly. The validator would have
-- been advisory.
--
-- This file makes it structural, with no new columns and no policy
-- rewrite: a BEFORE INSERT/UPDATE trigger refuses `active` unless the
-- request is running as `service_role` — which is exactly what the Edge
-- Function uses and what no client can mint. So the single door to
-- `active` is the function, and the function's own rule is that it has
-- read the stored bytes, hashed them against the row, and run the
-- authoring contract over them.
--
-- ── What it deliberately does not do ──────────────────────────────
-- It validates nothing. It does not check hashes, sizes or geometry, and
-- it does not run on `draft` or `rejected` rows — those are the seller's
-- work items and stay freely writable. Its whole job is to make one
-- transition impossible from the outside.
--
-- Two limits, stated rather than implied:
--   • A session with **no JWT** (the SQL Editor, psql, a migration) is
--     allowed through: that is an operator, not an app request. It also
--     means a service-role key holder can bypass this by construction —
--     the key is the trust boundary, as it always was.
--   • An UPDATE that leaves `status='active'` unchanged is allowed only
--     while `sha256` and `storage_path` are also unchanged. Otherwise a
--     seller could keep a validated row live and quietly re-point it at
--     different bytes, which would make the validation a lie.
--
-- ── The client half ───────────────────────────────────────────────
-- `ShoeModelUploadService.publish` now inserts every row as `draft` and
-- calls the function, which writes the verdict. Applying this file
-- without that client change would break publishing with a raw 42501 —
-- the two ship together (V2.4).
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_product_model_server_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    claims       jsonb;
    caller_role  text;
BEGIN
    -- Only the transition *into* `active` is gated. Drafts, rejections and
    -- deletions are the seller's own business.
    IF NEW.status IS DISTINCT FROM 'active' THEN
        RETURN NEW;
    END IF;

    -- No JWT in the session means a direct SQL session (SQL Editor, psql,
    -- a migration) rather than a PostgREST request: an operator path, left
    -- open so an admin can resolve a stuck row without disabling this.
    claims := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb;
    caller_role := COALESCE(claims ->> 'role', '');
    IF caller_role = '' OR caller_role = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- An already-active row may be edited (metadata, material map, notes)
    -- as long as it still describes the same bytes. Re-pointing a live row
    -- at a different object has to go back through the validator.
    IF TG_OP = 'UPDATE'
       AND OLD.status = 'active'
       AND NEW.sha256 = OLD.sha256
       AND NEW.storage_path = OLD.storage_path THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'product_models rows reach status=''active'' only through the '
        'validate-shoe-model Edge Function (roadmap V2.4): it re-reads the '
        'stored bytes, checks them against this row''s sha256 and runs the '
        'authoring contract before publishing. Write the row as ''draft'' and '
        'call that function, or ask an admin.'
        USING ERRCODE = 'insufficient_privilege',
              HINT = 'The app does this automatically after a model upload.';
END;
$$;

COMMENT ON FUNCTION public.enforce_product_model_server_validation() IS
  'Virtual fitting V2.4: stops any non-service-role caller from writing product_models.status=''active'', so the validate-shoe-model Edge Function is the only door to a live model.';

DROP TRIGGER IF EXISTS trg_product_models_server_validation ON public.product_models;
CREATE TRIGGER trg_product_models_server_validation
  BEFORE INSERT OR UPDATE ON public.product_models
  FOR EACH ROW EXECUTE FUNCTION public.enforce_product_model_server_validation();

-- Verify after applying. As a service-role/operator session every statement
-- below succeeds; the last two are the interesting ones, because they show
-- the door shut from an `authenticated` request:
--
--   SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--    WHERE tgrelid = 'public.product_models'::regclass AND NOT tgisinternal;
--
--   BEGIN;
--     -- simulate a normal signed-in client
--     SET LOCAL ROLE authenticated;
--     SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"<uuid>"}';
--     -- this must fail with 42501 insufficient_privilege
--     UPDATE public.product_models SET status = 'active' WHERE id = <id>;
--   ROLLBACK;
--
--   BEGIN;
--     SET LOCAL ROLE authenticated;
--     SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"<uuid>"}';
--     -- this must succeed: drafts are the seller's own work item
--     UPDATE public.product_models SET status = 'draft' WHERE id = <id>;
--   ROLLBACK;
