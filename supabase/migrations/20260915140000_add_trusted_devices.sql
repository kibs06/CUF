-- ══════════════════════════════════════════════════════════════════
-- Trusted devices (ANQUI checklist item 16, Part B)
--
-- WHY: the app challenges a password login from a device the account
-- has never been seen on with an emailed 6-digit OTP (a step-up
-- challenge — NOT passwordless login). This table is the record of
-- which (user, device) pairs have already cleared that challenge.
--
-- Pair key: (user_id, device_id), NOT device_id alone. Several
-- accounts legitimately share one physical phone; trusting a device
-- for account A must never trust it for account B.
--
-- `device_id` is a client-generated UUID persisted in the app's
-- secure storage for the life of the install. It is deliberately
-- opaque: it is an identifier the client claims, not a secret, and it
-- is never used as an authentication factor on its own (it only
-- decides whether the OTP step-up is required; the password and
-- optional TOTP MFA still gate the session).
--
-- WRITE PATH: there is intentionally NO INSERT/UPDATE policy. Rows are
-- written only through public.trust_device(), which takes the user id
-- from auth.uid() so a client can never trust a device for someone
-- else. Readers get SELECT (the check) and DELETE (revoke) on their
-- own rows only.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.trusted_devices (
  user_id       uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id     text        NOT NULL,
  -- Best-effort human-readable label ("Samsung SM-A155F · Android 14")
  -- shown in the user's own device list so a row is recognisable.
  device_label  text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  -- When the device last CLEARED the step-up challenge (or was trusted
  -- implicitly because the account had TOTP MFA enabled — see
  -- lib/services/login_challenge_service.dart).
  trusted_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trusted_devices_pkey PRIMARY KEY (user_id, device_id),
  -- A device id is a UUID (36 chars); the bounds leave room for a
  -- future format change while rejecting empty/blank ids outright.
  CONSTRAINT trusted_devices_device_id_len
    CHECK (char_length(btrim(device_id)) BETWEEN 8 AND 128)
);

COMMENT ON TABLE public.trusted_devices IS
  'Per-(user_id, device_id) record of devices that have cleared the '
  'new-device email OTP step-up. Written only via public.trust_device().';

-- The security screen lists "your devices" newest-activity-first.
CREATE INDEX IF NOT EXISTS trusted_devices_user_recent_idx
  ON public.trusted_devices (user_id, last_seen_at DESC);

-- ────────────────────────────────────────────────────────────────
-- 2. RLS — read/revoke your own rows; admins may audit
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.trusted_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own trusted devices"
  ON public.trusted_devices;
CREATE POLICY "Users can read their own trusted devices"
  ON public.trusted_devices FOR SELECT
  USING (auth.uid() = user_id);

-- Revoking a device must force the OTP step-up again on its next
-- login, so DELETE is a first-class user action.
DROP POLICY IF EXISTS "Users can revoke their own trusted devices"
  ON public.trusted_devices;
CREATE POLICY "Users can revoke their own trusted devices"
  ON public.trusted_devices FOR DELETE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can read all trusted devices"
  ON public.trusted_devices;
CREATE POLICY "Admins can read all trusted devices"
  ON public.trusted_devices FOR SELECT
  USING (public.is_admin());

-- Grants: authenticated only (anon has no business here). No
-- INSERT/UPDATE grant — those go through the RPC below.
REVOKE ALL ON public.trusted_devices FROM anon;
GRANT SELECT, DELETE ON public.trusted_devices TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 3. Write path — public.trust_device()
--
-- Upserts the (auth.uid(), device) pair and bumps last_seen_at. Used
-- for BOTH cases the client needs:
--   • the device is already trusted → bumps last_seen_at
--   • the device just cleared the challenge → inserts the row
-- so the client only ever makes one call and cannot forget the bump.
--
-- SECURITY DEFINER is required: it is the only way to write the table
-- (no INSERT/UPDATE policy exists). auth.uid() is taken from the
-- JWT, never from an argument, so this cannot be used to trust a
-- device for another user. first_seen_at/trusted_at are preserved on
-- conflict — re-trusting a known device must not rewrite its history.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trust_device(
  p_device_id    text,
  p_device_label text DEFAULT NULL
)
RETURNS public.trusted_devices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id   text := btrim(coalesce(p_device_id, ''));
  v_row  public.trusted_devices;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_id) < 8 OR char_length(v_id) > 128 THEN
    RAISE EXCEPTION 'A valid device_id is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.trusted_devices AS td (user_id, device_id, device_label)
  VALUES (
    v_user,
    v_id,
    nullif(btrim(coalesce(p_device_label, '')), '')
  )
  ON CONFLICT (user_id, device_id) DO UPDATE
    SET last_seen_at  = now(),
        -- Never blank out a label we already have.
        device_label  = coalesce(excluded.device_label, td.device_label)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

COMMENT ON FUNCTION public.trust_device(text, text) IS
  'Trusts the calling user''s device (or refreshes last_seen_at). The '
  'user is taken from auth.uid(); the client cannot write other users'' rows.';

REVOKE ALL ON FUNCTION public.trust_device(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trust_device(text, text) TO authenticated;
