-- ══════════════════════════════════════════════════════════════════
-- First-time Terms & Privacy acceptance timestamp (pgTAP) — run by CI via
-- `supabase test db` (workflow: supabase-migrations.yml).
--
-- Covers migration 20261024000000_add_terms_accepted_at.sql: the
-- server-side source of truth for AuthGate's once-ever Terms gate for
-- first-time social customers.
--
--   1. Schema: column exists, timestamptz, defaults to NULL (gate shows).
--   2. A customer (owner) can stamp ONLY this column on their own row —
--      the acceptance write AuthGate performs.
--   3. The same owner still cannot change role / seller_status in the
--      same update (guard trigger from 20260903000000 still holds).
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(6);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'terms-customer@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e0000000-0000-0000-0000-000000000001', 'Terry Customer', 'terms-customer@test.local', 'customer', 'none');

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_column(
  'public', 'profiles', 'terms_accepted_at',
  '1: terms_accepted_at column exists on profiles'
);

select col_type_is(
  'public', 'profiles', 'terms_accepted_at',
  'timestamp with time zone',
  '2: the acceptance stamp is a timestamptz'
);

-- ══ 2. OWNER CAN STAMP ONLY THIS COLUMN ═══════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$ update public.profiles
     set terms_accepted_at = now()
     where id = 'e0000000-0000-0000-0000-000000000001' $$,
  '3: a customer can stamp their own terms acceptance'
);

select ok(
  (select terms_accepted_at from public.profiles where id = 'e0000000-0000-0000-0000-000000000001') is not null,
  '4: the stamp persists after the update'
);

-- ══ 3. GUARD TRIGGER STILL HOLDS ═════════════════════════════════
select throws_ok(
  $$ update public.profiles
     set role = 'admin', terms_accepted_at = now()
     where id = 'e0000000-0000-0000-0000-000000000001' $$,
  'P0001', 'Cannot change your own role.',
  '5: stamping acceptance cannot smuggle a role change'
);

select throws_ok(
  $$ update public.profiles
     set seller_status = 'pending', terms_accepted_at = now()
     where id = 'e0000000-0000-0000-0000-000000000001' $$,
  'P0001', 'Cannot change your own seller_status.',
  '6: stamping acceptance cannot smuggle a seller_status change'
);

reset role;
select * from finish();
rollback;
