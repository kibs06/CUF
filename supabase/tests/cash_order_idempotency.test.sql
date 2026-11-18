-- ══════════════════════════════════════════════════════════════════
-- pgTAP: a retried cash checkout cannot become a second order
--
-- Cash orders are inserted straight from the app, so the only thing that can
-- tell a retry apart from a new purchase is the key the customer's checkout
-- screen carries. These assertions pin the database half of that: one order
-- per (customer, key), the guard scoped per customer, and the NULL keys of
-- every older/POS row still free to repeat.
--
-- The last two assertions are the promise that this did not disturb GCash:
-- its one-open-checkout index still refuses a second awaiting order.
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/cash_order_idempotency.test.sql
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(8);

-- ── 1. the shape of the guard ─────────────────────────────────────
select has_column(
  'public', 'orders', 'idempotency_key',
  '1: orders carry the checkout key');

select has_index(
  'public', 'orders', 'uq_orders_customer_idempotency_key',
  '2: the per-customer key index exists');

-- ── fixtures ──────────────────────────────────────────────────────
-- Two customers, so "same key, different customer" is observable.
select set_config('request.jwt.claims',
  '{"sub":"f1000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000001','authenticated','authenticated','idem-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000002','authenticated','authenticated','idem-b@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('f1000000-0000-0000-0000-000000000001','IDEM Customer A','idem-a@test.local','customer'),
  ('f1000000-0000-0000-0000-000000000002','IDEM Customer B','idem-b@test.local','customer')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

-- ── 2. the first insert claims the key ────────────────────────────
insert into public.orders
  (id, customer_id, total_amount, status, payment_status, payment_method,
   source, order_code, idempotency_key)
values
  ('f1000000-0000-0000-0000-0000000000a1',
   'f1000000-0000-0000-0000-000000000001', 500, 'pending', 'unpaid', 'cash',
   'online', 'IDEMA001', 'key-cash-a-0001');

select is(
  (select count(*)::int from public.orders
    where customer_id = 'f1000000-0000-0000-0000-000000000001'),
  1,
  '3: the first cash order is stored');

-- ── 3. the retry is the same order, not a second one ──────────────
select throws_ok(
  $$insert into public.orders
      (id, customer_id, total_amount, status, payment_status, payment_method,
       source, order_code, idempotency_key)
    values
      ('f1000000-0000-0000-0000-0000000000a2',
       'f1000000-0000-0000-0000-000000000001', 500, 'pending', 'unpaid',
       'cash', 'online', 'IDEMA002', 'key-cash-a-0001')$$,
  '23505',
  null,
  '4: the same key from the same customer is a duplicate');

select is(
  (select count(*)::int from public.orders
    where customer_id = 'f1000000-0000-0000-0000-000000000001'),
  1,
  '5: the refused retry left no second row behind');

-- ── 4. the key is per customer, and NULL keys still repeat ────────
insert into public.orders
  (id, customer_id, total_amount, status, payment_status, payment_method,
   source, order_code, idempotency_key)
values
  ('f1000000-0000-0000-0000-0000000000b1',
   'f1000000-0000-0000-0000-000000000002', 500, 'pending', 'unpaid', 'cash',
   'online', 'IDEMB001', 'key-cash-a-0001');

select is(
  (select count(*)::int from public.orders
    where idempotency_key = 'key-cash-a-0001'),
  2,
  '6: another customer may use the same key');

insert into public.orders
  (id, customer_id, total_amount, status, payment_status, payment_method,
   source, order_code)
values
  ('f1000000-0000-0000-0000-0000000000c1',
   'f1000000-0000-0000-0000-000000000001', 100, 'received', 'paid', 'cash',
   'pos', 'IDEMP001'),
  ('f1000000-0000-0000-0000-0000000000c2',
   'f1000000-0000-0000-0000-000000000001', 100, 'received', 'paid', 'cash',
   'pos', 'IDEMP002');

select is(
  (select count(*)::int from public.orders
    where idempotency_key is null
      and customer_id = 'f1000000-0000-0000-0000-000000000001'),
  2,
  '7: keyless POS orders still repeat freely');

-- ── 5. GCash's own cap is untouched ───────────────────────────────
insert into public.orders
  (id, customer_id, total_amount, status, payment_status, payment_method,
   source, order_code)
values
  ('f1000000-0000-0000-0000-0000000000d1',
   'f1000000-0000-0000-0000-000000000002', 500,
   'awaiting_payment_confirmation', 'pending', 'gcash', 'online', 'IDEMG001');

select throws_like(
  $$insert into public.orders
      (id, customer_id, total_amount, status, payment_status, payment_method,
       source, order_code)
    values
      ('f1000000-0000-0000-0000-0000000000d2',
       'f1000000-0000-0000-0000-000000000002', 500,
       'awaiting_payment_confirmation', 'pending', 'gcash', 'online',
       'IDEMG002')$$,
  '%uq_orders_one_awaiting_payment_confirmation_per_customer%',
  '8: one open GCash checkout per customer still holds');

select * from finish();
rollback;
