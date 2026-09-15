-- ══════════════════════════════════════════════════════════════════
-- Server-side enforcement of the trusted-device step-up
-- (ANQUI checklist item 16, Part B)
--
-- WHY THIS MIGRATION EXISTS
-- -------------------------
-- 20260915140000 added `trusted_devices` and an email OTP step-up, but
-- the check lived ONLY in the Flutter client
-- (lib/services/login_challenge_service.dart). A hand-crafted client
-- — or `curl` against the REST API — could sign in with a stolen
-- password and read/write the whole private schema, never sending the
-- code, because nothing on the server looked at whether the device had
-- ever cleared the step-up. A client-side gate is a UX affordance, not
-- a security control.
--
-- WHAT MAKES THE CHECK UNFORGEABLE
-- --------------------------------
-- The device proves possession with a SECRET, never with its id. The
-- id alone is public knowledge (it is a UUID the client generates), so
-- "trusted_devices has a row for this device_id" cannot be the test —
-- a hand-crafted client would just claim that id.
--
--   1. `public.device_secrets` holds a SHA-256 hash of a 32-byte
--      random secret, one per (user_id, device_id). The table has RLS
--      enabled, NO policies and NO grants: no client can read, write
--      or even see it. Only the SECURITY DEFINER functions below touch
--      it.
--   2. The client sends `x-cufmai-device: <device_id>:<secret>` on
--      every request. PostgREST exposes request headers to SQL as the
--      `request.headers` setting, so RLS can see it.
--   3. `public.device_is_trusted()` hashes the presented secret and
--      compares it to the stored hash for `auth.uid()` + that device.
--      Wrong secret ⇒ mismatch. Right secret for someone else's
--      account ⇒ no row for (auth.uid(), device).
--   4. The secret can only be minted by `public.trust_device()`, which
--      requires a session whose JWT `amr` already proves possession:
--        • amr contains `otp` (a completed email OTP — signup
--          verification or the new-device challenge; both produce it)
--        • amr contains `magiclink`, or aal = 'aal2' (TOTP MFA).
--      A password-only session (amr = ["password"]) is REFUSED, so a
--      stolen password cannot mint a secret for the attacker's device.
--      Verified against the real stack: `verifyOtp(type: signup)` and
--      `verifyOtp(type: email)` both yield amr ["otp"].
--
-- This closes the loop: to get past the gate you need the device
-- secret (something only the trusted device has) OR the emailed code
-- OR an MFA factor. A stolen password alone gets you an empty result
-- set on the private tables — reads are FILTERED by RLS, so the
-- failure is silent emptiness, not a crash.
--
-- ROLLOUT: ENFORCEMENT IS OFF IN THIS MIGRATION
-- --------------------------------------------
-- Applying this migration is SAFE for the app that is installed today.
-- The policy is wired up but `device_enforcement_policy
-- .enforcement_enabled` is FALSE, so `device_is_trusted()` returns true
-- and nothing is denied.
--
-- That default is deliberate and load-bearing. Turning enforcement on
-- is an INSTANT breaking change for any client that does not send the
-- header: every already-installed APK would start seeing empty
-- orders/cart/messages. So the order is:
--
--   1. Apply this migration (no behaviour change).
--   2. Ship the app build that mints + sends the device secret.
--   3. Flip enforcement on once that build is out:
--        select public.set_device_enforcement(true);   -- as an admin
--      or: update public.device_enforcement_policy
--             set enforcement_enabled = true where id;
--
-- Step 3 is the only step that changes behaviour, and it is a single
-- row — no schema change, no deploy.
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. The secret store — invisible to every client role
--
-- One row per trusted device. The composite FK to trusted_devices
-- means a secret can only exist for a device that is actually trusted,
-- and revoking the device (DELETE on trusted_devices) cascades the
-- secret away — so a revoked device cannot keep its old secret alive.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.device_secrets (
  user_id     uuid        NOT NULL,
  device_id   text        NOT NULL,
  -- SHA-256 of the client's 32-byte secret. Stored as a hash because
  -- this is a bearer credential: a leaked table dump must not hand an
  -- attacker a working device token. (No per-row salt is needed — the
  -- secret is 256 bits of CSPRNG output, so it is not brute-forceable
  -- and not subject to a rainbow-table attack.)
  secret_hash bytea       NOT NULL,
  minted_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT device_secrets_pkey PRIMARY KEY (user_id, device_id),
  CONSTRAINT device_secrets_device_fk
    FOREIGN KEY (user_id, device_id)
    REFERENCES public.trusted_devices(user_id, device_id)
    ON DELETE CASCADE
);

COMMENT ON TABLE public.device_secrets IS
  'SHA-256 hash of the per-(user, device) step-up secret the client sends '
  'as x-cufmai-device. No grants: reachable only through the SECURITY '
  'DEFINER helpers, so no client can read or forge a device secret.';

COMMENT ON COLUMN public.device_secrets.secret_hash IS
  'sha256 of a 32-byte CSPRNG secret (extensions.digest(secret, ''sha256'')).';

ALTER TABLE public.device_secrets ENABLE ROW LEVEL SECURITY;
-- No policies are intentional: with RLS enabled and no policy, NOTHING
-- is visible through the table API. The REVOKE below is belt-and-braces
-- (and makes the intent explicit): the table is not part of the public
-- API surface at all.
REVOKE ALL ON public.device_secrets FROM anon, authenticated, PUBLIC;

-- ────────────────────────────────────────────────────────────────
-- 2. The rollout switch
--
-- A one-row table rather than a GUC or an env var, because policy
-- functions can read a table (SECURITY DEFINER, owned by postgres,
-- RLS+no-policies ⇒ invisible to clients) but cannot read the app
-- server's environment.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.device_enforcement_policy (
  id                  boolean     NOT NULL DEFAULT true,
  enforcement_enabled boolean     NOT NULL DEFAULT false,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          uuid,
  CONSTRAINT device_enforcement_policy_pkey PRIMARY KEY (id),
  -- Single-row table: `id` is a boolean that can only be true.
  CONSTRAINT device_enforcement_policy_single_row CHECK (id)
);

COMMENT ON TABLE public.device_enforcement_policy IS
  'Single-row rollout switch for trusted-device enforcement. FALSE means '
  'device_is_trusted() allows everything (safe for clients that predate the '
  'device header). Flip with public.set_device_enforcement(true).';

INSERT INTO public.device_enforcement_policy (id, enforcement_enabled)
VALUES (true, false)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.device_enforcement_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.device_enforcement_policy FROM anon, authenticated, PUBLIC;

-- ────────────────────────────────────────────────────────────────
-- 3. Helpers
-- ────────────────────────────────────────────────────────────────

-- The rollout switch, readable from a policy (clients cannot see the
-- table it reads).
CREATE OR REPLACE FUNCTION public.device_enforcement_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT dep.enforcement_enabled
       FROM public.device_enforcement_policy dep
      WHERE dep.id),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.device_enforcement_enabled() FROM PUBLIC;
-- Granted to anon as well as authenticated on purpose: policies are
-- evaluated for whatever role runs the query, and a SECURITY DEFINER
-- helper still needs EXECUTE from the CALLING role. The RLS recursion
-- canary caught exactly this class of bug before ("permission denied
-- for function" on an anon query), so do not narrow this.
GRANT EXECUTE ON FUNCTION public.device_enforcement_enabled() TO anon, authenticated;

COMMENT ON FUNCTION public.device_enforcement_enabled() IS
  'True when trusted-device enforcement is switched on. Reads the '
  'admin-only device_enforcement_policy table via SECURITY DEFINER.';

-- Does the CURRENT session already prove account possession?
--   • amr contains "otp"       → a completed email OTP (signup verify
--                                or the new-device challenge)
--   • amr contains "magiclink" → the same code arrived as a link
--   • aal = 'aal2'             → a second factor (TOTP MFA) cleared
-- A password login is amr ["password"] / aal1 ⇒ false.
-- jsonb containment is used rather than an exact match because GoTrue
-- stamps each amr entry with a timestamp ({method, timestamp}).
CREATE OR REPLACE FUNCTION public.session_proves_possession()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    (auth.jwt() -> 'amr') @> '[{"method":"otp"}]'::jsonb
    OR (auth.jwt() -> 'amr') @> '[{"method":"magiclink"}]'::jsonb
    OR (auth.jwt() ->> 'aal') = 'aal2',
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.session_proves_possession() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.session_proves_possession() TO anon, authenticated;

COMMENT ON FUNCTION public.session_proves_possession() IS
  'True when the JWT amr/aal already proves account possession (email OTP, '
  'magic link, or aal2 MFA) — as opposed to a password-only session.';

-- THE GATE. True when the calling user presents a valid device secret
-- for a device that is trusted for THEM. This is what the restrictive
-- policies call.
--
-- SECURITY DEFINER is required to read public.device_secrets (no
-- grants). The user id comes from the JWT, never from an argument, so
-- the check cannot be aimed at another account.
--
-- STABLE, and evaluated once per row of the target table. The cost per
-- row is one primary-key lookup on (user_id, device_id) — the digest is
-- computed once for the presented secret, not per row.
CREATE OR REPLACE FUNCTION public.device_is_trusted()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_uid    uuid := auth.uid();
  v_raw    text;
  v_sep    integer;
  v_device text;
  v_secret text;
  v_hash   bytea;
BEGIN
  -- Rollout switch: while off, nothing is denied (see the header note).
  IF NOT public.device_enforcement_enabled() THEN
    RETURN true;
  END IF;

  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  -- `request.headers` is set by PostgREST for every request. It is
  -- absent when the statement runs outside PostgREST (psql, pgTAP,
  -- migrations) — and current_setting(..., true) then returns NULL
  -- rather than raising.
  BEGIN
    v_raw := (current_setting('request.headers', true))::json
               ->> 'x-cufmai-device';
  EXCEPTION WHEN others THEN
    -- A malformed headers setting is not a reason to allow anything.
    RETURN false;
  END;

  IF v_raw IS NULL THEN
    RETURN false;
  END IF;

  -- Wire format: "<device_id>:<secret>". Reject anything that cannot
  -- possibly be a well-formed token before touching the table.
  v_raw   := btrim(v_raw);
  v_sep   := position(':' in v_raw);
  IF v_sep < 9 THEN
    RETURN false;
  END IF;

  v_device := btrim(substring(v_raw from 1 for v_sep - 1));
  v_secret := btrim(substring(v_raw from v_sep + 1));

  -- device_id is a UUID (36 chars) but the table allows 8..128; the
  -- secret is 32 random bytes hex-encoded (64 chars).
  IF char_length(v_device) < 8 OR char_length(v_secret) < 32 THEN
    RETURN false;
  END IF;

  SELECT ds.secret_hash INTO v_hash
    FROM public.device_secrets ds
   WHERE ds.user_id = v_uid
     AND ds.device_id = v_device;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN v_hash = extensions.digest(v_secret, 'sha256');
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.device_is_trusted() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.device_is_trusted() TO anon, authenticated;

COMMENT ON FUNCTION public.device_is_trusted() IS
  'True when the caller presents a valid x-cufmai-device secret for a device '
  'trusted for auth.uid() (or when enforcement is switched off). Used by the '
  'restrictive "Require a trusted device" policies.';

-- ────────────────────────────────────────────────────────────────
-- 3b. Read-only probe: "would the gate let this session through?"
--
-- The app needs to tell "this table is empty" apart from "this session
-- is being gated", because RLS filters denied rows instead of raising —
-- an un-stepped-up session sees an empty order list, not an error. It
-- uses this on startup to decide whether to ask for a code, which is
-- what makes turning enforcement on self-healing for installs that
-- already have a session (rather than silently blanking their screens).
-- Returns the caller's own state and nothing else, so it leaks nothing.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.device_gate_open()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT public.device_is_trusted();
$$;

REVOKE ALL ON FUNCTION public.device_gate_open() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.device_gate_open() TO authenticated;

COMMENT ON FUNCTION public.device_gate_open() IS
  'True when the calling session may use the device-gated tables — i.e. it '
  'presents a valid x-cufmai-device secret, is an admin, or enforcement is '
  'switched off. Lets the app distinguish "empty" from "gated".';

-- ────────────────────────────────────────────────────────────────
-- 4. Rewrite the minting path so it BOTH records the device and
--    returns a fresh secret — and refuses a password-only session
--
-- The return type changes (it now also carries the secret), so the old
-- signature is dropped rather than replaced. Nothing else depends on
-- it: the only caller is the Flutter client, via PostgREST.
-- ────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.trust_device(text, text);

CREATE OR REPLACE FUNCTION public.trust_device(
  p_device_id    text,
  p_device_label text DEFAULT NULL
)
RETURNS TABLE (
  device_id     text,
  device_label  text,
  first_seen_at timestamptz,
  last_seen_at  timestamptz,
  trusted_at    timestamptz,
  device_secret text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_user   uuid := auth.uid();
  v_id     text := btrim(coalesce(p_device_id, ''));
  v_label  text := nullif(btrim(coalesce(p_device_label, '')), '');
  v_secret text;
  v_row    public.trusted_devices;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- THE STEP-UP GATE (server side). Recording a trusted device — and
  -- therefore minting the secret that satisfies the policies — requires
  -- a session that already proved possession of the account. Without
  -- this, anyone holding a stolen password could mint a secret on their
  -- own device and walk straight past the gate.
  IF NOT public.session_proves_possession() THEN
    RAISE EXCEPTION
      'A verified email code or a second factor is required to trust a new device'
      USING ERRCODE = '42501';
  END IF;

  IF char_length(v_id) < 8 OR char_length(v_id) > 128 THEN
    RAISE EXCEPTION 'A valid device_id is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.trusted_devices AS td (user_id, device_id, device_label)
  VALUES (v_user, v_id, v_label)
  -- ON CONFLICT ON CONSTRAINT, not (user_id, device_id): this function's
  -- RETURNS TABLE declares output parameters named device_id/device_label,
  -- and plpgsql resolves a bare column reference in a conflict target to the
  -- PARAMETER (ERROR: column reference "device_id" is ambiguous). Naming the
  -- constraint sidesteps the shadowing without renaming the JSON keys the
  -- client reads.
  ON CONFLICT ON CONSTRAINT trusted_devices_pkey DO UPDATE
    SET last_seen_at = now(),
        -- Never blank out a label we already have.
        device_label = coalesce(excluded.device_label, td.device_label)
  RETURNING * INTO v_row;

  -- Mint a new secret (and rotate any previous one — re-trusting a
  -- device must invalidate the old credential, not add a second one).
  -- gen_random_bytes is pgcrypto's CSPRNG; the client keeps the plain
  -- secret, this table keeps only its digest.
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.device_secrets AS ds (user_id, device_id, secret_hash, minted_at)
  VALUES (v_user, v_id, extensions.digest(v_secret, 'sha256'), now())
  ON CONFLICT ON CONSTRAINT device_secrets_pkey DO UPDATE
    SET secret_hash = excluded.secret_hash,
        minted_at   = excluded.minted_at;

  RETURN QUERY
    SELECT v_row.device_id,
           v_row.device_label,
           v_row.first_seen_at,
           v_row.last_seen_at,
           v_row.trusted_at,
           v_secret;
END;
$fn$;

COMMENT ON FUNCTION public.trust_device(text, text) IS
  'Trusts the calling user''s device and returns a fresh device secret. '
  'Requires a session that already proved possession (amr otp/magiclink, or '
  'aal2) — a password-only session is refused, so the step-up cannot be '
  'skipped by a hand-crafted client.';

REVOKE ALL ON FUNCTION public.trust_device(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trust_device(text, text) TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 5. Admin control for the rollout switch
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_device_enforcement(p_enabled boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only an admin can change device enforcement'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.device_enforcement_policy
     SET enforcement_enabled = coalesce(p_enabled, false),
         updated_at          = now(),
         updated_by          = auth.uid()
   WHERE id
  RETURNING enforcement_enabled INTO v_now;

  RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.set_device_enforcement(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_device_enforcement(boolean) TO authenticated;

COMMENT ON FUNCTION public.set_device_enforcement(boolean) IS
  'Admin-only. Switches trusted-device enforcement on/off at runtime and '
  'records who did it. Returns the new state.';

-- ────────────────────────────────────────────────────────────────
-- 6. The policies
--
-- A RESTRICTIVE `FOR ALL` policy is ANDed with the existing permissive
-- policies, so it can only ever REMOVE access — it never grants
-- anything a user could not already do. (WITH CHECK is spelled out
-- explicitly so writes are gated too, not just reads.)
--
-- The sweep is dynamic over every RLS-enabled public table so a NEW
-- table is covered automatically instead of silently unprotected —
-- the same philosophy as rls_recursion_canary.test.sql. Tables that a
-- session legitimately needs BEFORE the step-up is cleared are
-- exempted explicitly, below.
--
-- ⚠️ A new BOOTSTRAP table (one the login/sign-up/step-up flow itself
-- reads or writes) must be added to v_exempt, or it will be gated and
-- the challenge will deadlock itself.
-- ────────────────────────────────────────────────────────────────
-- The exemption list, exposed as a FUNCTION so the installer below, the
-- verification queries, and the pgTAP guard all read the SAME list. A second
-- copy is how a table quietly falls out of the gate.
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

    -- ── public catalog: readable by anon already ──
    'products', 'product_images', 'product_variants', 'product_color_images',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',

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

-- The sweep, as a RE-RUNNABLE function rather than a one-shot DO block.
--
-- WHY a function: the sweep only covers tables that exist when it runs, so a
-- table added by a LATER migration would be created WITHOUT the gate. Making it
-- callable means any migration that adds an RLS table ends with
-- `select public.install_device_gate_policies();` and the gap closes. The
-- pgTAP guard (admin_account_security.test.sql) fails the build if one forgets,
-- so "new tables are protected by default" is enforced rather than promised.
CREATE OR REPLACE FUNCTION public.install_device_gate_policies()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r record;
  v_exempt  text[] := public.device_gate_exempt_tables();
  v_created integer := 0;
BEGIN
  -- Pass 1 — drop the policy from EVERY RLS table, exempt ones included.
  -- Splitting this out from the create pass is what makes it correct when the
  -- exemption list CHANGES: without it, a table newly added to the list would
  -- silently keep the policy from a previous run.
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE c.relkind = 'r'
       AND c.relrowsecurity
       AND ns.nspname = 'public'
     ORDER BY c.relname
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      'Require a trusted device', r.relname
    );
  END LOOP;

  -- Pass 2 — (re)create it on everything that is not exempt.
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE c.relkind = 'r'
       AND c.relrowsecurity
       AND ns.nspname = 'public'
       AND NOT (c.relname = ANY (v_exempt))
     ORDER BY c.relname
  LOOP
    EXECUTE format(
      'CREATE POLICY %I ON public.%I '
      'AS RESTRICTIVE FOR ALL TO authenticated '
      'USING (public.device_is_trusted() OR public.is_admin()) '
      'WITH CHECK (public.device_is_trusted() OR public.is_admin())',
      'Require a trusted device', r.relname
    );
    v_created := v_created + 1;
  END LOOP;

  IF v_created = 0 THEN
    -- Never let a silent no-op look like success.
    RAISE EXCEPTION 'install_device_gate_policies() gated 0 tables — '
      'the policy sweep found nothing to protect';
  END IF;

  RETURN v_created;
END;
$fn$;

COMMENT ON FUNCTION public.install_device_gate_policies() IS
  'Drops and recreates the RESTRICTIVE "Require a trusted device" policy on '
  'every RLS table that is not exempt; returns how many it gated. Re-run it at '
  'the end of any migration that adds an RLS table. NOT granted to any client '
  'role — it is a maintenance function.';

-- Deliberately not granted to anon/authenticated: a client has no business
-- re-running the sweep, and the restrictive policies do not call it.
REVOKE ALL ON FUNCTION public.install_device_gate_policies() FROM PUBLIC;

SELECT public.install_device_gate_policies();

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- 1. Enforcement is wired but OFF (nothing is denied yet):
--      SELECT public.device_enforcement_enabled();                 -- false
--      SELECT count(*) FROM pg_policies
--        WHERE policyname = 'Require a trusted device';            -- > 0
--      SELECT tablename FROM pg_policies
--        WHERE policyname = 'Require a trusted device'
--        ORDER BY tablename;                    -- the gated set, no
--                                               -- bootstrap tables in it
--
--    And nothing RLS-protected is left ungated by accident:
--      SELECT c.relname
--        FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
--       WHERE c.relkind='r' AND c.relrowsecurity AND ns.nspname='public'
--         AND NOT (c.relname = ANY (public.device_gate_exempt_tables()))
--         AND NOT EXISTS (SELECT 1 FROM pg_policies p
--                          WHERE p.schemaname='public'
--                            AND p.tablename=c.relname
--                            AND p.policyname='Require a trusted device');
--      -- must return 0 rows
--
-- 2. The gate itself, as an authenticated user whose JWT has no step-up:
--      SET request.jwt.claims = '{"sub":"...","role":"authenticated"}';
--      SET request.headers    = '{"x-cufmai-device":""}';
--      SELECT public.device_is_trusted();   -- false once enforcement is on
--
-- 3. A password-only session cannot mint a secret:
--      SELECT public.trust_device('some-device-id');   -- 42501
--
-- Full proof-of-behaviour lives in supabase/tests/
-- trusted_device_enforcement.test.sql.
