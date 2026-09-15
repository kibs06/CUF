-- ══════════════════════════════════════════════════════════════════
-- Server-side trusted-device enforcement (pgTAP)
-- — run by CI via `supabase test db`
--
-- Covers migration 20260915150000_enforce_trusted_devices.sql: the
-- device SECRET the client must present, the amr-gated minting path,
-- and the restrictive "Require a trusted device" policies.
--
-- WHY THIS FILE EXISTS SEPARATELY from trusted_devices.test.sql:
-- that file covers the (user, device) bookkeeping from
-- 20260915140000. This one covers the part that makes the step-up a
-- SECURITY control instead of a client-side gate — i.e. that a
-- hand-crafted client holding only a stolen password really is denied.
--
-- The whole file runs in ONE transaction that is rolled back, so the
-- `enforcement_enabled = true` it sets for its own purposes cannot leak
-- into the live database or any other test file.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(44);

-- ── helpers ───────────────────────────────────────────────────────
-- A well-formed device token: "<device_id>:<secret>".
create or replace function public.tmp_device_header(p_device text, p_secret text)
returns text language sql immutable as $$
  select json_build_object('x-cufmai-device', p_device || ':' || p_secret)::text;
$$;

create or replace function public.tmp_jwt(p_user uuid, p_method text, p_aal text)
returns text language sql immutable as $$
  select json_build_object(
    'sub', p_user,
    'role', 'authenticated',
    'amr', json_build_array(json_build_object('method', p_method)),
    'aal', p_aal
  )::text;
$$;

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'enf-customer@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'enf-other@test.local',    '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'enf-admin@test.local',    '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('d0000000-0000-0000-0000-00000000000a', 'Enf Customer', 'enf-customer@test.local', 'customer', 'none'),
  ('d0000000-0000-0000-0000-00000000000b', 'Enf Other',    'enf-other@test.local',    'customer', 'none'),
  ('d0000000-0000-0000-0000-00000000000c', 'Enf Admin',    'enf-admin@test.local',    'admin',    'none');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('d0000000-0000-0000-0000-0000000000f1', null, null, 'Enforcement Probe Product', 10, true);

insert into public.cart_items (id, user_id, product_id, quantity)
values ('d0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-00000000000a',
        'd0000000-0000-0000-0000-0000000000f1', 1);

insert into public.orders (id, customer_id, total_amount, status)
values ('d0000000-0000-0000-0000-0000000000e2', 'd0000000-0000-0000-0000-00000000000a', 100, 'pending');

-- The customer's trusted device: id `enf-device-1`, secret 64×'a'.
insert into public.trusted_devices (user_id, device_id, device_label)
values ('d0000000-0000-0000-0000-00000000000a', 'enf-device-1', 'Enforcement Phone');

insert into public.device_secrets (user_id, device_id, secret_hash)
values ('d0000000-0000-0000-0000-00000000000a', 'enf-device-1',
        extensions.digest(repeat('a', 64), 'sha256'));

-- ══ 1. Structure ══════════════════════════════════════════════════
-- WHY NAMES AND A FLOOR, NOT AN EXACT COUNT:
-- this used to assert `count(*) = 26`, which meant every legitimately-gated
-- new table (pickup_reservations was the first) failed the suite until someone
-- edited the number. That trains the next author to bump a constant instead of
-- asking the question the assertion exists for — is THIS table private? The
-- self-maintaining half of that question lives in admin_account_security.test.sql
-- ("every RLS table is either device-gated or explicitly exempt"), which holds
-- the gate's default-deny property with no constant to update. What is left
-- for this file is the other direction: that the specific account-sensitive
-- tables are STILL gated, and that nobody mass-un-gated the sweep.
select is(
  (select count(*) from pg_policies
    where policyname = 'Require a trusted device'
      and tablename = any(array[
        'orders', 'order_items', 'cart_items', 'messages', 'notifications',
        'customer_addresses', 'payment_intents', 'vouchers', 'voucher_redemptions',
        'sales_transactions', 'bulk_reservations', 'pickup_reservations'
      ]))::int,
  12,
  'the device policy is installed on the high-value private tables, including both reservation systems'
);

select cmp_ok(
  (select count(*) from pg_policies where policyname = 'Require a trusted device')::int,
  '>=',
  27,
  'the sweep gated at least its historical 26 tables plus pickup_reservations (a mass un-gating regression, not a new table, fails here)'
);

-- A bootstrap table must NEVER be gated, or the step-up locks itself out
-- (the challenge reads trusted_devices, and the login lockout counter
-- writes failed_logins strictly before any step-up can exist).
select ok(
  not exists (
    select 1 from pg_policies
    where policyname = 'Require a trusted device'
      and tablename in ('profiles', 'trusted_devices', 'failed_logins',
                        'device_secrets', 'device_enforcement_policy',
                        'products', 'stores', 'banners', 'reviews')
  ),
  'no bootstrap or public-catalog table carries the device policy'
);

select ok(
  (select bool_or(permissive = 'RESTRICTIVE') from pg_policies
    where policyname = 'Require a trusted device'),
  'the policy is RESTRICTIVE (it can only remove access, never grant it)'
);

-- Both USING and WITH CHECK are set, so writes are gated as well as reads.
select ok(
  (select bool_and(qual is not null and with_check is not null) from pg_policies
    where policyname = 'Require a trusted device'),
  'the policy gates reads AND writes (USING + WITH CHECK)'
);

-- ══ 2. Enforcement OFF by default: nothing is denied ══════════════
select is(public.device_enforcement_enabled(), false,
  'enforcement ships switched OFF (safe to apply before clients are updated)');

select is(public.device_is_trusted(), true,
  'while enforcement is off, device_is_trusted() allows everything');

-- ══ 3. Enforcement ON ═════════════════════════════════════════════
update public.device_enforcement_policy set enforcement_enabled = true where id;
select is(public.device_enforcement_enabled(), true, 'the rollout switch can be turned on');

-- ── 3a. Password-only session, NO device header ───────────────────
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
select set_config('request.headers', '{}', true);
set role authenticated;

select is(public.device_is_trusted(), false, 'no header ⇒ device is not trusted');
select is((select count(*) from public.cart_items)::int, 0,
  'gated SELECT returns nothing without a device secret (cart_items)');
select is((select count(*) from public.orders)::int, 0,
  'gated SELECT returns nothing without a device secret (orders)');
-- The bootstrap exemption is what keeps the app able to render at all.
select is((select count(*) from public.profiles)::int, 3,
  'profiles stays readable pre-step-up (role routing still works)');
select is((select count(*) from public.trusted_devices)::int, 1,
  'trusted_devices stays readable pre-step-up (the challenge reads it)');
select is((select count(*) from public.products)::int, 1,
  'public catalog stays readable pre-step-up');

select throws_ok(
  $$insert into public.cart_items (user_id, product_id, quantity)
    values ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000f1', 1)$$,
  '42501', null,
  'gated INSERT is refused without a device secret'
);

-- A DELETE that matches nothing raises no error, so the meaningful
-- assertion is that the row SURVIVES (checked again as postgres below).
delete from public.cart_items where id = 'd0000000-0000-0000-0000-0000000000e1';
update public.cart_items set quantity = 99 where id = 'd0000000-0000-0000-0000-0000000000e1';
reset role;

select is((select count(*) from public.cart_items
            where id = 'd0000000-0000-0000-0000-0000000000e1')::int, 1,
  'gated DELETE did not remove the row');
select is((select quantity from public.cart_items
            where id = 'd0000000-0000-0000-0000-0000000000e1')::int, 1,
  'gated UPDATE did not modify the row');

-- ── 3b. Malformed / wrong / forged tokens are refused ─────────────
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);

select set_config('request.headers',
  public.tmp_device_header('enf-device-1', repeat('b', 64)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'a WRONG secret for a real device id is refused');
reset role;

select set_config('request.headers',
  public.tmp_device_header('enf-device-1', ''), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'a device id with no secret at all is refused (the id is not a credential)');
reset role;

-- A device the user has never trusted, even with a well-formed token.
select set_config('request.headers',
  public.tmp_device_header('enf-not-mine-1', repeat('a', 64)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'an unknown device id is refused');
reset role;

select set_config('request.headers', '{"x-cufmai-device":"not-json-ok"}', true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'a malformed token is refused');
reset role;

-- ── 3c. Another user's session cannot borrow the secret ──────────
-- Same device id, same secret, different account: the pair is keyed by
-- (user_id, device_id), so this must NOT open user A's rows.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000b', 'password', 'aal1'), true);
select set_config('request.headers',
  public.tmp_device_header('enf-device-1', repeat('a', 64)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'user B presenting user A''s device+secret sees nothing of A''s');
reset role;

-- ── 3d. The valid secret opens the gate ──────────────────────────
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
select set_config('request.headers',
  public.tmp_device_header('enf-device-1', repeat('a', 64)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 1,
  'the correct secret opens gated reads');
select lives_ok(
  $$insert into public.cart_items (user_id, product_id, quantity)
    values ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000f1', 2)$$,
  'the correct secret permits gated writes'
);
delete from public.cart_items where id = 'd0000000-0000-0000-0000-0000000000e1';
reset role;
select is((select count(*) from public.cart_items
            where id = 'd0000000-0000-0000-0000-0000000000e1')::int, 0,
  'the correct secret permits gated deletes');
-- NOTE: the device secret table itself must stay invisible to clients.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
set role authenticated;
select throws_ok(
  'select count(*) from public.device_secrets',
  '42501', null,
  'device_secrets is not even granted to authenticated (no secret fishing)'
);
reset role;

-- ── 3e. Admin bypass ─────────────────────────────────────────────
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000c', 'password', 'aal1'), true);
select set_config('request.headers', '{}', true);
set role authenticated;
select is((select count(*) from public.orders)::int, 1,
  'an admin is not blocked by the device gate (admin portal still works)');
reset role;

-- ── 3f. anon is untouched ────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":"anon"}', true);
set role anon;
select is((select count(*) from public.products)::int, 1,
  'anon access is unaffected (the policy is scoped TO authenticated)');
reset role;

-- ── 3g. Switching enforcement off again restores access ──────────
update public.device_enforcement_policy set enforcement_enabled = false where id;
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
select set_config('request.headers', '{}', true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 1,
  'turning enforcement off restores access for clients without a secret (rollback path)');
reset role;

update public.device_enforcement_policy set enforcement_enabled = true where id;

-- ══ 4. The minting gate: only a stepped-up session may trust a device ══
-- 4a. Password-only session ⇒ refused. This is the whole point: a
--     stolen password must not be able to mint a secret.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
set role authenticated;
select throws_ok(
  $$select public.trust_device('attacker-device-1', 'Stolen Phone')$$,
  '42501',
  'A verified email code or a second factor is required to trust a new device',
  'a password-only session cannot mint a device secret'
);
reset role;

-- 4b. An email-OTP session may mint, and the minted secret works.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'otp', 'aal1'), true);
set role authenticated;
create temp table enf_minted as
  select device_id, device_secret from public.trust_device('enf-fresh-device', 'My New Phone');

select is((select char_length(device_secret) from enf_minted)::int, 64,
  'trust_device() returns a 64-char (32-byte) hex secret to an OTP-verified session');
select is((select count(*) from public.trusted_devices where device_id = 'enf-fresh-device')::int, 1,
  'trust_device() recorded the new device');

select set_config('request.headers',
  public.tmp_device_header('enf-fresh-device', (select device_secret from enf_minted)), true);
select is((select count(*) from public.cart_items)::int, 1,
  'the freshly minted secret immediately satisfies the gate');
reset role;

-- 4c. Re-trusting ROTATES the secret — the previous one must stop working.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'otp', 'aal1'), true);
set role authenticated;
create temp table enf_rotated as
  select device_secret from public.trust_device('enf-fresh-device', 'My New Phone');
reset role;

select ok(
  (select device_secret from enf_rotated) <> (select device_secret from enf_minted),
  're-trusting a device mints a NEW secret rather than reusing the old one'
);

select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
select set_config('request.headers',
  public.tmp_device_header('enf-fresh-device', (select device_secret from enf_minted)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'the ROTATED-OUT secret no longer opens the gate');
reset role;

select set_config('request.headers',
  public.tmp_device_header('enf-fresh-device', (select device_secret from enf_rotated)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 1,
  'the current secret does open the gate');
reset role;

-- 4d. aal2 (TOTP MFA) also satisfies the step-up — the documented
--     decision that an authenticator app counts as proving possession.
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000b', 'totp', 'aal2'), true);
set role authenticated;
select lives_ok(
  $$select public.trust_device('enf-mfa-device', 'MFA Phone')$$,
  'an aal2 (TOTP MFA) session may trust a device — MFA satisfies the step-up'
);
reset role;

-- 4e. magiclink sessions count too (its 6-digit code is the same OTP).
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000b', 'magiclink', 'aal1'), true);
set role authenticated;
select lives_ok(
  $$select public.trust_device('enf-magic-device', 'Magic Link Phone')$$,
  'a magiclink session may trust a device'
);
reset role;

-- ══ 5. Revoking a device destroys its secret ═════════════════════
select is(
  (select count(*) from public.device_secrets
    where user_id = 'd0000000-0000-0000-0000-00000000000a'
      and device_id = 'enf-device-1')::int,
  1,
  'the trusted device has a stored secret'
);

delete from public.trusted_devices
 where user_id = 'd0000000-0000-0000-0000-00000000000a'
   and device_id = 'enf-device-1';

select is(
  (select count(*) from public.device_secrets
    where user_id = 'd0000000-0000-0000-0000-00000000000a'
      and device_id = 'enf-device-1')::int,
  0,
  'revoking the device cascades its secret away (a revoked device cannot keep working)'
);

select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
select set_config('request.headers',
  public.tmp_device_header('enf-device-1', repeat('a', 64)), true);
set role authenticated;
select is((select count(*) from public.cart_items)::int, 0,
  'the revoked device''s old secret is dead — it must clear the step-up again');
reset role;

-- ══ 6. Only an admin may flip the switch ═════════════════════════
select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000a', 'password', 'aal1'), true);
set role authenticated;
select throws_ok(
  'select public.set_device_enforcement(false)',
  '42501', 'Only an admin can change device enforcement',
  'a normal user cannot switch enforcement off'
);
reset role;

select set_config('request.jwt.claims',
  public.tmp_jwt('d0000000-0000-0000-0000-00000000000c', 'password', 'aal1'), true);
set role authenticated;
select is(public.set_device_enforcement(false), false,
  'an admin can switch enforcement off (returns the new state)');
select is(public.set_device_enforcement(true), true,
  'an admin can switch enforcement back on');
reset role;

select * from finish();
rollback;
