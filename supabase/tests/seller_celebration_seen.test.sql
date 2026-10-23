-- ══════════════════════════════════════════════════════════════════
-- Seller approval celebration "seen" flag (pgTAP) — run by CI via
-- `supabase test db` (workflow: supabase-migrations.yml).
--
-- Covers migration 20261023000000_add_celebration_seen_flag.sql: the
-- server-side source of truth for the one-time "You're now part of the
-- CUFMAI family!" welcome.
--
--   1. Schema: column exists, boolean, NOT NULL, DEFAULT FALSE.
--   2. An approved seller (owner) can flip ONLY this flag on their own
--      row — the celebration hand-off write AuthGate performs.
--   3. The same owner still cannot change role / seller_status /
--      locked application columns in the same update (guard trigger
--      from 20260903000000 still holds).
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(9);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'celebrate-seller@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('d0000000-0000-0000-0000-000000000001', 'Celia Seller', 'celebrate-seller@test.local', 'seller', 'approved');

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_column(
  'public', 'profiles', 'has_seen_approval_celebration',
  '1: has_seen_approval_celebration column exists on profiles'
);

select col_type_is(
  'public', 'profiles', 'has_seen_approval_celebration',
  'boolean',
  '2: the flag is a boolean'
);

select col_not_null(
  'public', 'profiles', 'has_seen_approval_celebration',
  '3: the flag is NOT NULL'
);

select col_default_is(
  'public', 'profiles', 'has_seen_approval_celebration',
  'false',
  '4: the flag defaults to FALSE (celebration shows until tapped)'
);

-- ══ 2. OWNER CAN FLIP ONLY THIS FLAG ═════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$ update public.profiles
     set has_seen_approval_celebration = true
     where id = 'd0000000-0000-0000-0000-000000000001' $$,
  '5: an approved seller can mark their own celebration as seen'
);

select is(
  (select has_seen_approval_celebration from public.profiles where id = 'd0000000-0000-0000-0000-000000000001'),
  true,
  '6: the flag stays true after the update'
);

-- ══ 3. GUARD TRIGGER STILL HOLDS ═════════════════════════════════
select throws_ok(
  $$ update public.profiles
     set role = 'admin', has_seen_approval_celebration = true
     where id = 'd0000000-0000-0000-0000-000000000001' $$,
  'P0001', 'Cannot change your own role.',
  '7: flipping the flag cannot smuggle a role change'
);

select throws_ok(
  $$ update public.profiles
     set seller_status = 'pending', has_seen_approval_celebration = true
     where id = 'd0000000-0000-0000-0000-000000000001' $$,
  'P0001', 'Cannot change your own seller_status.',
  '8: flipping the flag cannot smuggle a seller_status change'
);

select throws_ok(
  $$ update public.profiles
     set store_name = 'Sneaky Store', has_seen_approval_celebration = true
     where id = 'd0000000-0000-0000-0000-000000000001' $$,
  'P0001', 'Application details are locked after submission.',
  '9: flipping the flag cannot smuggle a locked store_name change'
);

reset role;
select * from finish();
rollback;
