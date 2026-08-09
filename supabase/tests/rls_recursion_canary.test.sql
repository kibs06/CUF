-- ══════════════════════════════════════════════════════════════════
-- RLS recursion canary (pgTAP) — run by CI via `supabase test db`
--
-- WHY THIS EXISTS:
-- A policy on table T whose USING clause references T again (directly
-- or through the RLS chain) COMPILES fine — Postgres only fails at
-- QUERY time with error 42P17 ("infinite recursion detected in policy
-- for relation \"T\""). Applying the migrations is therefore NOT
-- enough: the policies must actually be EXERCISED. That is exactly
-- what this file does.
--
-- It emulates an authenticated customer and the anon role, then runs
-- SELECT count(*) against EVERY public table with RLS enabled. Any
-- 42P17 (or any other error) aborts the canary and fails the CI job.
-- New tables are covered automatically — no per-table upkeep.
--
-- This also catches two OTHER runtime-only policy bugs:
--   • permission-denied on a SECURITY DEFINER helper used in a policy
--     (e.g. is_admin() granted only to authenticated → anon queries on
--     any table with an admin policy blow up). The anon sweep below
--     is exactly what caught that.
--   • stale policies that error for the anon/authenticated roles.
--
-- Run locally:
--   supabase start
--   supabase test db
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(6);

-- ── helper: sweep every RLS-enabled public table ───────────────────
-- Runs as the CURRENT role (no SECURITY DEFINER!) so RLS applies and
-- any recursive policy raises here. The alias is `ns` and the counter
-- `cnt` on purpose — PL/pgSQL variables shadow SQL identifiers, so a
-- variable named `n` would clash with a pg_namespace alias named `n`.
create or replace function public.tmp_rls_canary_sweep()
returns void
language plpgsql
as $$
declare
  r record;
  cnt bigint;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where c.relkind = 'r'
      and c.relrowsecurity
      and ns.nspname = 'public'
    order by c.relname
  loop
    begin
      execute format('select count(*) from public.%I', r.relname) into cnt;
    exception when others then
      raise exception 'RLS error on table "%": %', r.relname, sqlerrm;
    end;
  end loop;
end
$$;

-- ── 1. authenticated customer can read every RLS table ─────────────
-- A fake JWT sub (a valid UUID that matches no profile) is fine: the
-- point is that the query EXECUTES without raising 42P17.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}',
  true
);
set role authenticated;

select lives_ok(
  'select public.tmp_rls_canary_sweep()',
  'authenticated: no RLS recursion (42P17) on any RLS-enabled table'
);

-- ── 2. admin helpers are callable and false for a normal user ──────
-- Runs AS the authenticated role, so these also prove authenticated
-- users have EXECUTE on the helpers (GRANT was set up by the
-- 20260809120000_fix_profiles_rls_recursion migration).
select is(public.is_admin(), false, 'is_admin() is false for a normal user');
select is(public.is_seller_or_admin(), false, 'is_seller_or_admin() is false for a normal user');

reset role;

-- ── 3. anon can read every RLS table ───────────────────────────────
select set_config(
  'request.jwt.claims',
  '{"sub":null,"role":"anon"}',
  true
);
set role anon;

select lives_ok(
  'select public.tmp_rls_canary_sweep()',
  'anon: no RLS recursion (42P17) on any RLS-enabled table'
);

reset role;

-- ── 4. structural: profiles admin policies use the helper ──────────
-- Catches a reintroduction of the self-referential policy early with
-- a clear message (the runtime sweep would also catch it, less clearly).
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname like 'Admins can %'
      and qual like '%is_admin()%'
  ),
  'profiles admin policies call is_admin() (no inline profiles subqueries)'
);

-- ── 5. direct regression for the reported production failure ───────
-- The exact query that broke the app (profile load on the auth gate
-- screen) — as a normal authenticated user.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}',
  true
);
set role authenticated;

select lives_ok(
  'select count(*) from public.profiles',
  'authenticated: selecting from profiles works (42P17 symptom is gone)'
);

select * from finish();
rollback;
