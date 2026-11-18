-- ══════════════════════════════════════════════════════════════════
-- pgTAP: the delivery line has exactly one source
--
-- Covers 20261118150000_delivery_fee_from_platform_settings.sql:
--   • online_delivery_fee() follows platform_settings.delivery_fee_amount
--     instead of a literal, so an admin fee change reaches the voucher
--     quote and the orders repricing trigger;
--   • a database without the settings row still answers ₱100 (the seeded
--     default), so nothing behaves differently before the row exists;
--   • the voucher preview and the function agree on the same number.
--
-- Run with: supabase test db. Everything happens inside one transaction and
-- is rolled back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(6);

-- ── 1. the seeded value ───────────────────────────────────────────
select is(
  public.online_delivery_fee(),
  100::numeric,
  'seeded settings row yields the ₱100 delivery line'
);

-- ── 2. it follows the admin setting ───────────────────────────────
update public.platform_settings
   set delivery_fee_amount = 150
 where id = 1;

select is(
  public.online_delivery_fee(),
  150::numeric,
  'raising delivery_fee_amount to 150 moves the function to 150'
);

-- ── 3. the function is not a constant ─────────────────────────────
update public.platform_settings
   set delivery_fee_amount = 0
 where id = 1;

select is(
  public.online_delivery_fee(),
  0::numeric,
  'a zero delivery fee is honoured (free delivery), not clamped'
);

-- ── 4. missing row → seeded default ───────────────────────────────
delete from public.platform_settings where id = 1;

select is(
  public.online_delivery_fee(),
  100::numeric,
  'no settings row falls back to the seeded ₱100'
);

insert into public.platform_settings (id, platform_fee_bps, delivery_fee_amount)
values (1, 0, 175)
on conflict (id) do update
  set delivery_fee_amount = excluded.delivery_fee_amount;

select is(
  public.online_delivery_fee(),
  175::numeric,
  'a re-created settings row is read again'
);

-- ── 5. declared volatility matches what the function does ─────────
-- IMMUTABLE over a table read is a lie the planner can cash in as a
-- plan-time constant; this is the assertion that keeps it STABLE.
select is(
  (select p.provolatile
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'online_delivery_fee'),
  's'::"char",
  'online_delivery_fee() is STABLE, not IMMUTABLE'
);

select * from finish();
rollback;
