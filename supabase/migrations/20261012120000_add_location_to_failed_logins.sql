-- ══════════════════════════════════════════════════════════════════
-- WHERE THE ATTEMPT CAME FROM — the attacker's approximate location
--
-- WHY: `failed_logins` already records the device and the IP address, and
-- both are shown to the account owner (lockout overlay + email) and to the
-- admin (Intruder / Suspicious Login). Neither answers the first question
-- anyone asks about a lockout — "where was this?" — and an IP address on its
-- own does not answer it for a human. This adds the city-level place that
-- address resolves to, the coordinate pair and the network, so the answer is
-- on the row instead of being looked up by hand in a third-party tool while
-- the account is locked.
--
-- ⚠️ WHAT THIS DATA IS NOT. An IP address identifies a NETWORK, not a person.
-- The lookup resolves to the city the address block is registered in — for a
-- mobile pool that is the carrier's hub, which can be a different city (and
-- sometimes a different region) from the one the device is physically in. The
-- columns are therefore `location` (a place name), `latitude`/`longitude` (the
-- centroid of that city, not a device position) — and every surface that shows
-- them says "approximate / city-level". Nothing may render these as a street
-- address, and no decision in this schema reads them: they are evidence ABOUT
-- a lockout, never an input to it.
--
-- The values are client-reported (the failing device resolved its own address
-- at the moment of the attempt), exactly like `ip_address` and `user_agent`
-- already are, and for the same reason: the attempt happens before any
-- authenticated session exists, so there is no server-side actor to attribute
-- it to. They are nullable and best-effort, so an install that cannot reach
-- the lookup writes NULL and nothing else changes.
--
-- Idempotent — safe to re-run. Requires 20260915160000 first.
-- ══════════════════════════════════════════════════════════════════

-- ── Columns ──────────────────────────────────────────────────────
-- `if not exists` on each, so a partially-applied run can be repeated.
ALTER TABLE public.failed_logins
  ADD COLUMN IF NOT EXISTS location  text;

ALTER TABLE public.failed_logins
  ADD COLUMN IF NOT EXISTS latitude  double precision;

ALTER TABLE public.failed_logins
  ADD COLUMN IF NOT EXISTS longitude double precision;

COMMENT ON COLUMN public.failed_logins.location IS
  'Approximate place the ip_address resolves to, e.g. "Manila, National '
  'Capital Region, Philippines". City-level only — an IP address identifies a '
  'network, not a person, and a mobile pool can resolve to a different city '
  'than the device is in. NULL when the lookup did not answer.';

COMMENT ON COLUMN public.failed_logins.latitude IS
  'Latitude of the resolved city''s centroid (not a device position), or NULL. '
  'Approximate by construction: see the `location` comment.';

COMMENT ON COLUMN public.failed_logins.longitude IS
  'Longitude of the resolved city''s centroid (not a device position), or '
  'NULL. Approximate by construction: see the `location` comment.';

-- ── The admin diagnostics must read them ─────────────────────────
-- `admin_account_security_overview` returns the lockout row field by field, so
-- a new column is invisible to it until the function is replaced. This is the
-- same function as 20260915160000 with the three location fields added to the
-- `lockouts` block; nothing else about it changes, and the grants below are
-- re-issued so a re-run cannot leave the function reachable by `anon`.
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
  -- Matched on all three identification shapes (see the header note of
  -- 20260915160000): the OTP send and login rows carry `actor_id`, while
  -- `user_signedup` carries the user only in `traits.user_id`. The email
  -- fallback is last and only for rows neither id carries.
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
  -- `location` / `latitude` / `longitude` are the city-level place the
  -- attempt's address resolves to — approximate by construction (see the
  -- column comments) and NULL on any row written before that migration.
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'failed_at',     f.failed_at,
               'ip_address',    f.ip_address,
               'user_agent',    f.user_agent,
               'location',      f.location,
               'latitude',      f.latitude,
               'longitude',     f.longitude,
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
    -- The location caveat sits with them: this is the screen where an admin
    -- is most likely to mistake a city for an address.
    'cannot_answer', jsonb_build_array(
      'Failed OTP attempts are not recorded: Supabase Auth rejects a wrong '
      'code without writing anything, so an empty timeline is NOT evidence '
      'that nobody tried.',
      'Codes that were emailed are known only from when GoTrue accepted the '
      'send request, not from delivery to the inbox.',
      'The device secret itself is never exposed — only whether one exists '
      'and when it was minted.',
      'A lockout''s location is city-level and comes from the IP address, '
      'which identifies a network rather than a person — a mobile connection '
      'can resolve to a different city than the device is actually in. It is '
      'not a street address, and it is recorded only from the migration that '
      'added it, so older rows are NULL.'
    ),
    'generated_at', now()
  );
END;
$fn$;

COMMENT ON FUNCTION public.admin_account_security_overview(uuid) IS
  'Admin-only diagnostics for one account (ANQUI item 16): trusted devices '
  'with credential presence, GoTrue''s OTP/sign-in event timeline, password '
  'lockout state (including the approximate, city-level location the '
  'attempt''s IP resolves to) and the device-enforcement switch. Deliberately '
  'reports what it CANNOT know (failed attempts are never recorded).';

REVOKE ALL ON FUNCTION public.admin_account_security_overview(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_account_security_overview(uuid)
  TO authenticated;
-- anon is NOT granted: an unauthenticated caller has no business enumerating
-- accounts, and is_admin() is false for it anyway.

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- The three columns exist and start NULL:
--   select column_name, data_type from information_schema.columns
--    where table_name = 'failed_logins'
--      and column_name in ('location', 'latitude', 'longitude');
--   -- 3 rows: text / double precision / double precision
--
-- The function still refuses a non-admin (must raise 42501) and still never
-- leaks a secret hash:
--   select public.admin_account_security_overview('<uuid>'::uuid);
--   select public.admin_account_security_overview('<uuid>'::uuid)::text
--          like '%secret_hash%';        -- false
--
-- A lockout row now carries its location:
--   select user_id, ip_address, location, latitude, longitude
--     from public.failed_logins order by failed_at desc limit 5;
--
-- As an admin, the diagnostics document still parses and names the caveat:
--   select jsonb_pretty(
--     public.admin_account_security_overview('<uuid>'::uuid) -> 'lockouts'
--   );
--   select public.admin_account_security_overview('<uuid>'::uuid)
--          -> 'cannot_answer' @> '["A lockout''s location is city-level and '
--          'comes from the IP address, which identifies a network rather than '
--          'a person — a mobile connection can resolve to a different city '
--          'than the device is actually in. It is not a street address, and '
--          'it is recorded only from the migration that added it, so older '
--          'rows are NULL."]'::jsonb;   -- true
--
-- Proof-of-behaviour: supabase/tests/admin_account_security.test.sql.
