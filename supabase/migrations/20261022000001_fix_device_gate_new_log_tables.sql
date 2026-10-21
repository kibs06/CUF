-- Fix Supabase Migrations failure on main (admin_account_security test 33):
-- 20261015000000 added two RLS tables without updating the device-gate
-- sweep, so the invariant "every RLS table is either device-gated or
-- explicitly exempt" failed with: have: account_session_log, seller_activity_log
--
-- Decision:
-- * account_session_log -> EXEMPT (like failed_logins). It is written by the
--   client immediately after sign-in / before sign-out, i.e. BEFORE any
--   step-up exists on a new device. Gating it would block a new device from
--   logging its own sign-in -- the exact state the admin UI exists to see.
--   Row-level protection stays in its own policies (own-rows for users,
--   is_admin() for admins); the gate would only add a device wall in front
--   of a login-time write.
-- * seller_activity_log -> GATED (like seller_application_audit_log). It is
--   trigger-written, admin-read audit trail. The installer call below draws
--   the standard RESTRICTIVE "Require a trusted device" policy over it
--   (which admins still satisfy via OR is_admin()).
CREATE OR REPLACE FUNCTION public.device_gate_exempt_tables()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    -- ── identity / the step-up flow itself ──
    'profiles',                   -- role routing + the profile load that
                                  -- decides which shell to show
    'trusted_devices',            -- the challenge READS this to decide
                                  -- whether to challenge; gating it would
                                  -- lock every new device out forever
    'device_secrets',             -- internal (no grants); gated for clarity
    'device_enforcement_policy',  -- internal (no grants)
    'failed_logins',              -- the login lockout counter is written
                                  -- during the password attempt, i.e.
                                  -- strictly BEFORE any step-up exists
    -- Login-time session claims (20261015000000): written by the client at
    -- sign-in/sign-out, before any step-up exists on a new device. Gating
    -- would lock a new device out of logging its own sign-in.
    'account_session_log',

    -- ── public catalog: readable by anon already ──
    'products', 'product_images', 'product_variants', 'product_color_images',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',
    -- virtual fitting V2.1 (`20260927180000_add_try_on_models.sql`): a seller's
    -- 3D handover. Exempt ON PURPOSE, and the opposite of a leak — an `active`
    -- row is world-readable already (that is what the RLS policy on that table
    -- says), and the gate would sit directly across the customer's product page,
    -- which reads this table to warm the renderer's model cache. Gating it would
    -- lock a customer out of the very bytes V3 hands to the camera. It holds
    -- nothing customer-private either: a storage path, a digest, a triangle
    -- count and the seller's own declared length, all of it the seller's own
    -- work.
    --
    -- ⚠️ Added 2026-09-28, found by `supabase/tests/admin_account_security.test.sql`
    -- assertion 31 in CI, not by hand — which is the guard doing its job: the
    -- table was created months after the sweep above and would otherwise have
    -- been gated silently the first time `install_device_gate_policies()` was
    -- re-run with the gate switched on. The hosted project's copy of this
    -- function still predates the entry (see `MIGRATIONS_LIVE_STATUS.md`), so
    -- re-apply this file before re-running that installer.
    'product_models',

    -- ── device-scoped, not account-sensitive: the push token is
    --    registered right after login and leaking it would give an
    --    attacker nothing they do not already have ──
    'device_tokens'
  ];
$$;

COMMENT ON FUNCTION public.device_gate_exempt_tables() IS
  'Tables deliberately outside the trusted-device gate, each for a concrete '
  'reason (see the comments at each entry). Shared by '
  'install_device_gate_policies() and the pgTAP guard so the two cannot drift.';

-- Gate seller_activity_log (and re-converge any other ungated table).
SELECT public.install_device_gate_policies();
