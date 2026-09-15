-- ══════════════════════════════════════════════════════════════════
-- Trusted devices (pgTAP) — run by CI via `supabase test db`
-- (workflow: supabase-migrations.yml).
--
-- Covers migration 20260915140000 (ANQUI checklist item 16, Part B).
-- This is the SECURITY-relevant half of the new-device email OTP
-- step-up, so it is asserted in SQL rather than only in Dart:
--
--   1. Schema: table, columns, (user_id, device_id) primary key, RLS on.
--   2. trust_device(): refuses an unauthenticated caller and a blank
--      device id; otherwise inserts for auth.uid() and NOT for anyone
--      else — the user is taken from the JWT, never from an argument.
--      NOTE: since 20260915150000 the caller must ALSO already be
--      stepped up (amr otp/magiclink, or aal2) — see
--      trusted_device_enforcement.test.sql for that gate. The fixtures
--      below therefore carry an otp amr claim, matching the real flow:
--      trust_device() is only ever called after the code was verified.
--   3. Re-trusting a known device refreshes last_seen_at and preserves
--      first_seen_at / trusted_at / device_label (history is not
--      rewritten, and a label we already have is never blanked).
--   4. Multi-account on one phone: the pair key is (user_id, device_id),
--      so trusting a device for A never trusts it for B.
--   5. RLS: a user reads/deletes only their own rows; there is NO
--      INSERT/UPDATE policy, so a direct client write is denied; anon
--      has no table grant at all; admins can read everything.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(30);

-- ── clear any JWT context ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'td-alice@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'td-bob@test.local',   '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'td-admin@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('c0000000-0000-0000-0000-00000000000a', 'Device Alice', 'td-alice@test.local', 'customer', 'none'),
  ('c0000000-0000-0000-0000-00000000000b', 'Device Bob',   'td-bob@test.local',   'customer', 'none'),
  ('c0000000-0000-0000-0000-00000000000c', 'Device Admin', 'td-admin@test.local', 'admin',    'none');

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_table('public', 'trusted_devices', '1: trusted_devices table exists');
select has_column('public', 'trusted_devices', 'device_id',     '2: device_id column exists');
select has_column('public', 'trusted_devices', 'device_label',  '3: device_label column exists');
select has_column('public', 'trusted_devices', 'first_seen_at', '4: first_seen_at column exists');
select has_column('public', 'trusted_devices', 'last_seen_at',  '5: last_seen_at column exists');
select has_column('public', 'trusted_devices', 'trusted_at',    '6: trusted_at column exists');
select col_is_pk(
  'public', 'trusted_devices', array['user_id', 'device_id'],
  '7: primary key is the (user_id, device_id) PAIR, not the device alone'
);
select ok(
  (select c.relrowsecurity
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'trusted_devices'),
  '8: RLS is enabled'
);

-- ══ 2. trust_device() — authentication + validation ═══════════════
-- No JWT at all: the function must refuse rather than write anything.
select throws_ok(
  $$ select public.trust_device('device-unauth-0001') $$,
  '42501', 'Not authenticated',
  '9: an unauthenticated caller cannot trust a device'
);

-- A stepped-up session (email OTP already verified) — see the note above.
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated",'
  '"amr":[{"method":"otp"}],"aal":"aal1"}',
  true
);

select throws_ok(
  $$ select public.trust_device('short') $$,
  '22023', 'A valid device_id is required',
  '10: a too-short device_id is rejected'
);

select throws_ok(
  $$ select public.trust_device('') $$,
  '22023', 'A valid device_id is required',
  '11: a blank device_id is rejected'
);

set local role authenticated;

select lives_ok(
  $$ select public.trust_device('device-alice-0001', 'Pixel 8 · Android 15') $$,
  '12: an authenticated user can trust their own device'
);

select is(
  (select count(*)::int from public.trusted_devices),
  1,
  '13: exactly one row exists after the first trust'
);

-- The row belongs to the JWT subject — there is no user argument to spoof.
select is(
  (select user_id::text from public.trusted_devices where device_id = 'device-alice-0001'),
  'c0000000-0000-0000-0000-00000000000a',
  '14: the row is written for auth.uid(), not for a caller-supplied user'
);

-- ══ 3. Re-trusting refreshes last_seen_at, preserves history ══════
reset role;
update public.trusted_devices
   set last_seen_at  = now() - interval '2 days',
       first_seen_at = now() - interval '5 days',
       trusted_at    = now() - interval '5 days'
 where device_id = 'device-alice-0001';
set local role authenticated;

select lives_ok(
  $$ select public.trust_device('device-alice-0001') $$,
  '15: re-trusting a known device succeeds (and does not error on the PK)'
);

select is(
  (select count(*)::int from public.trusted_devices),
  1,
  '16: re-trusting upserts instead of inserting a duplicate row'
);

reset role;
select ok(
  (select last_seen_at > now() - interval '1 minute'
     from public.trusted_devices where device_id = 'device-alice-0001'),
  '17: last_seen_at is bumped'
);
select ok(
  (select first_seen_at < now() - interval '4 days'
     from public.trusted_devices where device_id = 'device-alice-0001'),
  '18: first_seen_at is preserved'
);
select ok(
  (select trusted_at < now() - interval '4 days'
     from public.trusted_devices where device_id = 'device-alice-0001'),
  '19: trusted_at is preserved'
);
select is(
  (select device_label from public.trusted_devices where device_id = 'device-alice-0001'),
  'Pixel 8 · Android 15',
  '20: a later call without a label keeps the label we already had'
);

-- ══ 4. Direct writes are denied (no INSERT/UPDATE policy) ═════════
set local role authenticated;
select throws_ok(
  $$ insert into public.trusted_devices (user_id, device_id)
     values ('c0000000-0000-0000-0000-00000000000a', 'device-direct-0001') $$,
  '42501', 'new row violates row-level security policy for table "trusted_devices"',
  '21: a client cannot INSERT a trusted device directly'
);

-- ══ 5. Per-user isolation (multi-account on one phone) ════════════
-- Bob shares Alice's physical device (same device_id) but is a different
-- user. Alice's row must not make the device trusted for Bob, and neither
-- user may see the other's rows.
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000b","role":"authenticated",'
  '"amr":[{"method":"otp"}],"aal":"aal1"}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from public.trusted_devices),
  0,
  '22: Bob sees none of Alice''s devices (RLS SELECT)'
);
select lives_ok(
  $$ select public.trust_device('device-alice-0001', 'Pixel 8 · Android 15') $$,
  '23: Bob may trust the SAME physical device for his own account'
);
select is(
  (select count(*)::int from public.trusted_devices),
  1,
  '24: Bob''s trust is his own row, not Alice''s'
);
select is(
  (select user_id::text from public.trusted_devices where device_id = 'device-alice-0001'),
  'c0000000-0000-0000-0000-00000000000b',
  '25: the pair key is (user_id, device_id) — one phone, two accounts'
);

-- Bob's DELETE must not touch Alice's identical device row.
select lives_ok(
  $$ delete from public.trusted_devices where device_id = 'device-alice-0001' $$,
  '26: a user can revoke their own device'
);
reset role;
select is(
  (select count(*)::int from public.trusted_devices where user_id = 'c0000000-0000-0000-0000-00000000000a'),
  1,
  '27: revoking as Bob left Alice''s row for the same device intact'
);
select is(
  (select count(*)::int from public.trusted_devices where user_id = 'c0000000-0000-0000-0000-00000000000b'),
  0,
  '28: Bob''s own row is gone'
);

-- ══ 6. Admin read, anon lockout ═══════════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
  true
);
set local role authenticated;
select is(
  (select count(*)::int from public.trusted_devices),
  1,
  '29: an admin can read every trusted device'
);

reset role;
select set_config('request.jwt.claims', '{"sub":null,"role":"anon"}', true);
set local role anon;
select throws_ok(
  $$ select count(*) from public.trusted_devices $$,
  '42501',
  'permission denied for table trusted_devices',
  '30: anon has no grant on trusted_devices at all'
);

reset role;
select * from finish();
rollback;
