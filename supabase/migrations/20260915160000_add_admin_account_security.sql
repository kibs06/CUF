-- ══════════════════════════════════════════════════════════════════
-- Admin account-security diagnostics (ANQUI item 16 support tooling)
--
-- WHY: the new-device step-up is invisible from the admin portal. Before
-- this migration there was no way to answer the one support ticket it
-- generates — "I got a new phone and I can't get in" — with anything
-- other than guesswork. An admin could not even see whether the account
-- had a device recorded, let alone whether that device still held the
-- credential the gate checks.
--
-- WHAT IT READS (all server-side; none of it is client-reported):
--   • auth.users      — email confirmation, last sign-in, OTP send stamps
--   • public.profiles — role / seller status
--   • trusted_devices — every device the account has cleared
--   • device_secrets  — WHETHER a credential exists and when it was minted.
--                       The hash itself is never returned, and (see below)
--                       it never leaves this function as a value.
--   • auth.audit_log_entries — GoTrue's own event stream
--   • public.failed_logins   — the password lockout counter
--   • device_enforcement_policy — is the gate even switched on?
--
-- MEASURED, NOT ASSUMED. Two facts about that event stream were verified
-- against a real GoTrue before this was written, because both change what
-- the view is allowed to claim:
--
--   1. The action names and their user field DIFFER. `user_recovery_requested`
--      (the OTP send) sets `actor_id` to the user, but `user_signedup` sets
--      `actor_id` to 00000000-…-0000 (the service role) and puts the real
--      user in `traits.user_id`. A filter on `actor_id` alone therefore MISSES
--      every signup event, so all three shapes are matched below.
--   2. A WRONG CODE LEAVES NO TRACE. `verify` with a bad token returns 403
--      from GoTrue without touching the database, so failed attempts are not
--      recorded anywhere. The response says so explicitly (see
--      `cannot_answer`) rather than letting an absence of events read as
--      "nobody tried" — the exact wrong conclusion in a lockout ticket.
--
-- The `ip_address` column exists on the audit table but GoTrue does not
-- populate it in this stack, so it is returned only when present and the
-- UI must not promise it.
--
-- ACCESS: a SECURITY DEFINER function gatekept by public.is_admin(), because
-- it reaches into the `auth` schema and past the RLS on device_secrets.
-- It takes the user from the ARGUMENT (that is the point — an admin is
-- investigating someone else's account) and authorises the CALLER, not the
-- subject, which is the one place in this schema where that is correct.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_account_security_overview(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_account     jsonb;
  v_email       text;
  v_devices     jsonb;
  v_events      jsonb;
  v_lockouts    jsonb;
  v_enforcement jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only an admin can read account security diagnostics'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'A user id is required' USING ERRCODE = '22023';
  END IF;

  -- ── the account ─────────────────────────────────────────────────
  -- Built FROM auth.users with a LEFT JOIN to profiles, so an account
  -- that never got a profile row still renders (and shows up as the
  -- anomaly it is) instead of looking like "no such user".
  SELECT
    jsonb_build_object(
      'user_id',             u.id,
      'email',               u.email,
      'has_profile',         (p.id IS NOT NULL),
      'full_name',           p.full_name,
      'role',                coalesce(p.role, 'none'),
      'seller_status',       p.seller_status,
      'email_confirmed',     (u.email_confirmed_at IS NOT NULL),
      'email_confirmed_at',  u.email_confirmed_at,
      'confirmation_sent_at', u.confirmation_sent_at,
      'recovery_sent_at',    u.recovery_sent_at,
      'last_sign_in_at',     u.last_sign_in_at,
      'created_at',          u.created_at
    ),
    u.email
  INTO v_account, v_email
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE u.id = p_user_id;

  IF v_account IS NULL THEN
    RAISE EXCEPTION 'No account with id %', p_user_id USING ERRCODE = 'P0002';
  END IF;

  -- ── trusted devices, with whether each still holds a credential ──
  -- `has_secret` is the diagnostic that matters most: a device row with
  -- NO secret is the "this phone is known but the gate will refuse it"
  -- state — the pairing left behind by a client that predates the
  -- server-side gate. It reads as a cleared device in the app and as a
  -- denial at the server, which is exactly why it needs to be visible.
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'device_id',        d.device_id,
               'device_label',     d.device_label,
               'first_seen_at',    d.first_seen_at,
               'last_seen_at',     d.last_seen_at,
               'trusted_at',       d.trusted_at,
               'has_secret',       (s.device_id IS NOT NULL),
               'secret_minted_at', s.minted_at
             )
             ORDER BY d.last_seen_at DESC
           ),
           '[]'::jsonb
         )
  INTO v_devices
  FROM public.trusted_devices d
  -- Only existence and the mint time are selected — never secret_hash.
  LEFT JOIN public.device_secrets s
    ON s.user_id = d.user_id AND s.device_id = d.device_id
  WHERE d.user_id = p_user_id;

  -- ── the OTP / sign-in timeline ──────────────────────────────────
  -- Matched on all three identification shapes (see the header note):
  -- the OTP send and login rows carry `actor_id`, while `user_signedup`
  -- carries the user only in `traits.user_id`. The email fallback is
  -- last and only for rows neither id carries.
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'at',     e.created_at,
               'action', e.payload->>'action',
               'kind',   CASE e.payload->>'action'
                           WHEN 'user_recovery_requested'    THEN 'otp_emailed'
                           WHEN 'user_confirmation_requested' THEN 'confirmation_emailed'
                           WHEN 'user_signedup'              THEN 'account_created'
                           WHEN 'login'                      THEN 'signed_in'
                           WHEN 'token_refreshed'             THEN 'session_refreshed'
                           WHEN 'user_updated'                THEN 'account_updated'
                           ELSE 'other'
                         END,
               'ip_address', nullif(e.ip_address, '')
             )
             ORDER BY e.created_at DESC
           ),
           '[]'::jsonb
         )
  INTO v_events
  FROM (
    SELECT a.created_at, a.payload, a.ip_address
      FROM auth.audit_log_entries a
     WHERE a.payload->>'actor_id' = p_user_id::text
        OR a.payload->'traits'->>'user_id' = p_user_id::text
        OR (v_email IS NOT NULL
            AND lower(a.payload->>'actor_username') = lower(v_email))
     ORDER BY a.created_at DESC
     LIMIT 100
  ) e;

  -- ── password lockout state ──────────────────────────────────────
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'failed_at',     f.failed_at,
               'ip_address',    f.ip_address,
               'user_agent',    f.user_agent,
               'status',        f.status,
               'attempt_count', f.attempt_count,
               'locked_until',  f.locked_until
             )
             ORDER BY f.failed_at DESC
           ),
           '[]'::jsonb
         )
  INTO v_lockouts
  FROM public.failed_logins f
  WHERE f.user_id = p_user_id;

  -- ── is the gate even switched on? ───────────────────────────────
  -- Without this an admin cannot tell "the feature is off and their
  -- phone is fine" from "the feature is on and their device is denied".
  SELECT jsonb_build_object(
           'enabled',    public.device_enforcement_enabled(),
           'updated_at', dep.updated_at,
           'updated_by', dep.updated_by
         )
  INTO v_enforcement
  FROM public.device_enforcement_policy dep
  WHERE dep.id;

  RETURN jsonb_build_object(
    'account',        v_account,
    'enforcement',    coalesce(v_enforcement, '{}'::jsonb),
    'devices',        v_devices,
    'otp_challenges', v_events,
    'lockouts',       v_lockouts,
    -- Stated in the payload, not just in a doc, so the caveat is in front of
    -- the person reading the timeline at the moment they might misread it.
    'cannot_answer', jsonb_build_array(
      'Failed OTP attempts are not recorded: Supabase Auth rejects a wrong '
      'code without writing anything, so an empty timeline is NOT evidence '
      'that nobody tried.',
      'Codes that were emailed are known only from when GoTrue accepted the '
      'send request, not from delivery to the inbox.',
      'The device secret itself is never exposed — only whether one exists '
      'and when it was minted.'
    ),
    'generated_at', now()
  );
END;
$fn$;

COMMENT ON FUNCTION public.admin_account_security_overview(uuid) IS
  'Admin-only diagnostics for one account (ANQUI item 16): trusted devices '
  'with credential presence, GoTrue''s OTP/sign-in event timeline, password '
  'lockout state and the device-enforcement switch. Deliberately reports what '
  'it CANNOT know (failed attempts are never recorded).';

REVOKE ALL ON FUNCTION public.admin_account_security_overview(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_account_security_overview(uuid)
  TO authenticated;
-- anon is NOT granted: an unauthenticated caller has no business enumerating
-- accounts, and is_admin() is false for it anyway.

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- As an admin:
--   select jsonb_pretty(
--     public.admin_account_security_overview('<uuid>'::uuid)::jsonb
--   );
-- As a normal user (must raise 42501):
--   select public.admin_account_security_overview('<uuid>'::uuid);
--
-- The returned document must never contain a secret hash:
--   select public.admin_account_security_overview('<uuid>'::uuid)::text
--          like '%secret_hash%';        -- false
--
-- Full proof-of-behaviour: supabase/tests/admin_account_security.test.sql.
