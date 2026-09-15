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
-- Tables the role cannot SELECT at all are SKIPPED with a NOTICE (see
-- the privilege check in tmp_rls_canary_sweep): Postgres rejects the
-- statement on the table grant before RLS is ever evaluated, so there
-- is no policy to exercise. That is a deliberate grant decision (e.g.
-- gcash_payment_decision_audit is granted to authenticated only), not
-- a policy bug. The "at least one table swept" assertion below keeps
-- that skip from silently turning the anon sweep into a no-op.
--
-- Run locally:
--   supabase start
--   supabase test db
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(7);

-- ── helper: sweep every RLS-enabled public table ───────────────────
-- Runs as the CURRENT role (no SECURITY DEFINER!) so RLS applies and
-- any recursive policy raises here. The alias is `ns` and the counter
-- `cnt` on purpose — PL/pgSQL variables shadow SQL identifiers, so a
-- variable named `n` would clash with a pg_namespace alias named `n`.
create or replace function public.tmp_rls_canary_sweep()
returns integer
language plpgsql
as $$
declare
  r record;
  cnt bigint;
  swept integer := 0;
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
    -- No table-level SELECT for this role ⇒ the statement is rejected
    -- before RLS runs, so there is nothing to exercise. Skip it (and
    -- say so) rather than reporting a policy failure that isn't one.
    -- A missing grant on a table a role CAN reach still raises below,
    -- because then the denial comes from inside the policy chain.
    if not has_table_privilege(
      current_user, format('public.%I', r.relname), 'select'
    ) then
      raise notice 'canary: skipping public.% — % has no SELECT privilege',
        r.relname, current_user;
      continue;
    end if;
    begin
      execute format('select count(*) from public.%I', r.relname) into cnt;
      swept := swept + 1;
    exception when others then
      raise exception 'RLS error on table "%": %', r.relname, sqlerrm;
    end;
  end loop;
  return swept;
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

-- Guard: the anon sweep must still be doing real work. Without this,
-- revoking anon SELECT across the schema would make the sweep above
-- pass vacuously (every table skipped) instead of failing loudly.
select cmp_ok(
  public.tmp_rls_canary_sweep(), '>', 0,
  'anon: the sweep exercised at least one RLS-enabled table'
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
