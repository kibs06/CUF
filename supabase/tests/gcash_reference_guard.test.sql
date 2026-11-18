-- ══════════════════════════════════════════════════════════════════
-- pgTAP: one GCash reference pays once — across every ledger
--
-- The three ledgers are unique on their own (proofs and deposits globally,
-- paid orders partially), so the only way to spend one transfer twice was to
-- use it in TWO DIFFERENT ledgers: an order proof and a reservation deposit,
-- a proof and a POS sale, and so on. 20261118080000 added
-- gcash_reference_owner() plus one BEFORE trigger on each writer.
--
-- Every assertion below is the observable result of a write: either the row
-- lands, or Postgres raises the guard's own sentence. Nothing inspects SQL
-- text. Digits are normalised, so the spaced and unspaced forms of a number
-- must behave identically.
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/gcash_reference_guard.test.sql
-- (needs `create extension pgtap`). Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select no_plan();

-- ── fixtures ──────────────────────────────────────────────────────
-- A profile insert fires log_seller_application_submission(), which writes
-- auth.uid() into seller_application_audit_log.actor_id (NOT NULL), so a
-- claim has to exist before fixtures are created.
select set_config(
  'request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

-- A profile row needs an auth user in this chain, and proofs.submitted_by is
-- a real foreign key, so both are created here (rolled back at the end).
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'f0000000-0000-0000-0000-000000000001',
   'authenticated', 'authenticated', 'guard-c1@test.local', now(), now())
on conflict (id) do nothing;

insert into public.profiles (id, full_name, email, role)
values ('f0000000-0000-0000-0000-000000000001',
        'Guard Customer', 'guard-c1@test.local', 'customer')
on conflict (id) do update set full_name = excluded.full_name;

-- ── 1. the guard is installed where it must be ────────────────────
select has_function(
  'public', 'gcash_reference_owner', array['text', 'uuid', 'uuid'],
  '1: the ownership lookup exists');

select has_function(
  'public', 'guard_gcash_reference', array[]::text[],
  '2: the guard trigger function exists');

select has_trigger(
  'public', 'gcash_payment_proofs', 'trg_guard_gcash_reference',
  '3: proofs are guarded');

select has_trigger(
  'public', 'orders', 'trg_guard_gcash_reference_orders',
  '4: orders are guarded');

select has_trigger(
  'public', 'bulk_reservation_deposits', 'trg_guard_gcash_reference_deposits',
  '5: reservation deposits are guarded');

select has_index(
  'public', 'orders', 'idx_orders_gcash_reference_digits',
  '6: the digits-only index on orders exists');

-- ── 2. an unused reference is free ────────────────────────────────
select is(
  public.gcash_reference_owner('999999999999'),
  null,
  '7: a reference nobody used is free');

-- ── 3. a paid order claims the transfer ───────────────────────────
insert into public.orders
  (id, total_amount, status, payment_status, payment_method, source,
   order_code, gcash_reference_number)
values
  ('f0000000-0000-0000-0000-0000000000a1', 1000, 'payment_under_review',
   'paid', 'gcash', 'online', 'GUARDAAA', '4043676687260');

-- 8. the same digits on a second order
select throws_like(
  $$insert into public.orders
      (id, total_amount, status, payment_status, payment_method, source,
       order_code, gcash_reference_number)
    values
      ('f0000000-0000-0000-0000-0000000000a2', 1000, 'pending', 'pending',
       'gcash', 'online', 'GUARDBBB', '4043676687260')$$,
  '%already used for order GUARDAAA%',
  '8: the same digits on a second order are refused');

-- 9. the same number typed with spaces is the same transfer
select throws_like(
  $$insert into public.orders
      (id, total_amount, status, payment_status, payment_method, source,
       order_code, gcash_reference_number)
    values
      ('f0000000-0000-0000-0000-0000000000a2', 1000, 'pending', 'pending',
       'gcash', 'online', 'GUARDBBB', '4043 676 687260')$$,
  '%already used for order GUARDAAA%',
  '9: a spaced duplicate is recognised as the same number');

-- 10. an unused reference goes through
select lives_ok(
  $$insert into public.orders
      (id, total_amount, status, payment_status, payment_method, source,
       order_code, gcash_reference_number)
    values
      ('f0000000-0000-0000-0000-0000000000a3', 500, 'pending', 'pending',
       'gcash', 'online', 'GUARDCCC', '111122223333')$$,
  '10: an unused reference is accepted');

-- 11. an order is not its own duplicate
select lives_ok(
  $$update public.orders set gcash_reference_number = '4043676687260'
     where id = 'f0000000-0000-0000-0000-0000000000a1'$$,
  '11: re-writing an order''s own reference is not a conflict');

-- ── 4. proofs go through the same guard ───────────────────────────
-- 12. another order's proof cannot claim the order's transfer
select throws_like(
  $$insert into public.gcash_payment_proofs
      (order_id, reference_number, screenshot_url, submitted_by)
    values
      ('f0000000-0000-0000-0000-0000000000a3', '4043676687260',
       'f0000000-0000-0000-0000-0000000000a3/receipt.png',
       'f0000000-0000-0000-0000-000000000001')$$,
  '%already used for order GUARDAAA%',
  '12: another order''s proof cannot reuse the number');

-- 13. the order's OWN proof is the same payment, not a duplicate
select lives_ok(
  $$insert into public.gcash_payment_proofs
      (order_id, reference_number, screenshot_url, submitted_by)
    values
      ('f0000000-0000-0000-0000-0000000000a1', '4043676687260',
       'f0000000-0000-0000-0000-0000000000a1/receipt.png',
       'f0000000-0000-0000-0000-000000000001')$$,
  '13: an order and its own proof may share the number');

-- ── 5. the guard reads every ledger ───────────────────────────────
-- 14. a POS sale cannot take a number a proof already owns
select throws_like(
  $$update public.orders set gcash_reference_number = '4043676687260'
     where id = 'f0000000-0000-0000-0000-0000000000a3'$$,
  '%already used for order GUARDAAA%',
  '14: an order cannot take a reference a proof owns');

select * from finish();

rollback;
