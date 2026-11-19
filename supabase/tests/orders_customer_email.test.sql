-- ══════════════════════════════════════════════════════════════════
-- pgTAP: the POS receipt email has a home on the order
--
-- Covers 20261119100000_orders_customer_email.sql:
--
--   1. Schema: the column exists, it is text, and the RPC exists.
--   2. The till that made the sale records the address; what lands is the
--      normalised one (trimmed, lowercased), not the string it sent.
--   3. A re-send replaces the address, so a corrected mailbox is the one the
--      next send prefills.
--   4. Someone else's seller, and the order's own customer, are both refused
--      with 42501 — the store that made the sale is the only writer.
--   5. A malformed or blank address never reaches the column, and neither
--      does a direct UPDATE that skips the RPC (the CHECK still holds).
--   6. anon cannot execute the function at all.
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/orders_customer_email.test.sql
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(13);

-- ── identity helper ───────────────────────────────────────────────
create or replace function pg_temp.claims(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

select set_config('request.headers', '{}', true);

-- ── 1. the shape of the feature ───────────────────────────────────
select has_column(
  'public', 'orders', 'customer_email',
  '1: orders carry the receipt email');

select col_type_is(
  'public', 'orders', 'customer_email', 'text',
  '2: it is free text, nullable for walk-ins who want no copy');

select has_function(
  'public', 'set_order_customer_email', array['uuid', 'text'],
  '3: one RPC writes it');

-- ── fixtures (as postgres: RLS bypassed) ──────────────────────────
-- Two sellers, each with their own store, and one customer: "another
-- seller cannot address my sale" needs a real second owner, not a role
-- string. Inserting a store writes a seller_activity_log row keyed to
-- auth.uid(), so the claim names the owner while the fixtures are built.
select pg_temp.claims('cd000000-0000-0000-0000-000000000011');

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000011','authenticated','authenticated','email-seller-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000012','authenticated','authenticated','email-seller-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000001','authenticated','authenticated','email-customer@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('cd000000-0000-0000-0000-000000000011','Email Seller A','email-seller-a@test.local','seller'),
  ('cd000000-0000-0000-0000-000000000012','Email Seller B','email-seller-b@test.local','seller'),
  ('cd000000-0000-0000-0000-000000000001','Email Customer','email-customer@test.local','customer')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values
  ('cd000000-0000-0000-0000-0000000000a1','cd000000-0000-0000-0000-000000000011','Email Store A','Test City');

select pg_temp.claims('cd000000-0000-0000-0000-000000000012');

insert into public.stores (id, owner_id, name, location)
values
  ('cd000000-0000-0000-0000-0000000000a2','cd000000-0000-0000-0000-000000000012','Email Store B','Test City');

-- One POS sale at Store A, the kind of row the receipt screen re-opens.
insert into public.orders
  (id, customer_id, store_id, total_amount, status, payment_status,
   payment_method, source, order_code)
values
  ('cd000000-0000-0000-0000-0000000000b1',
   'cd000000-0000-0000-0000-000000000001',
   'cd000000-0000-0000-0000-0000000000a1',
   1250, 'received', 'paid', 'cash', 'pos', 'EMAIL001');

-- ── 2. the till records the address ──────────────────────────────
select pg_temp.claims('cd000000-0000-0000-0000-000000000011');

select is(
  (select public.set_order_customer_email(
            'cd000000-0000-0000-0000-0000000000b1',
            '  Keith.Abalo@Example.COM ') ->> 'customer_email'),
  'keith.abalo@example.com',
  '4: the caller gets back the normalised address');

select is(
  (select customer_email from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b1'),
  'keith.abalo@example.com',
  '5: trimmed and lowercased, the column holds the delivery target');

-- ── 3. a corrected address replaces the old one ───────────────────
select public.set_order_customer_email(
  'cd000000-0000-0000-0000-0000000000b1',
  'keith.abalo+orders@gmail.com');

select is(
  (select customer_email from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b1'),
  'keith.abalo+orders@gmail.com',
  '6: a re-send overwrites, so the next prefill is the newest address');

-- ── 4. only the store that made the sale may write ────────────────
select pg_temp.claims('cd000000-0000-0000-0000-000000000012');

select throws_ok(
  $$select public.set_order_customer_email(
      'cd000000-0000-0000-0000-0000000000b1', 'other@example.com')$$,
  '42501',
  null,
  '7: another store''s seller is refused');

select pg_temp.claims('cd000000-0000-0000-0000-000000000001');

select throws_ok(
  $$select public.set_order_customer_email(
      'cd000000-0000-0000-0000-0000000000b1', 'other@example.com')$$,
  '42501',
  null,
  '8: the order''s own customer is refused — receipts are the till''s job');

-- ── 5. nothing half-typed reaches the column ──────────────────────
select pg_temp.claims('cd000000-0000-0000-0000-000000000011');

select throws_like(
  $$select public.set_order_customer_email(
      'cd000000-0000-0000-0000-0000000000b1', 'keith@example')$$,
  '%is not an email address%',
  '9: an address with no domain dot is refused');

select throws_like(
  $$select public.set_order_customer_email(
      'cd000000-0000-0000-0000-0000000000b1', '   ')$$,
  '%is empty%',
  '10: a blank field is refused rather than stored');

select throws_ok(
  $$select public.set_order_customer_email(
      'cd000000-0000-0000-0000-0000000000ff', 'keith@example.com')$$,
  'P0002',
  null,
  '11: an order that does not exist is refused');

-- The RPC is not the only writer a future migration might add: the CHECK
-- has to hold on its own.
select throws_ok(
  $$update public.orders set customer_email = 'not-an-address'
     where id = 'cd000000-0000-0000-0000-0000000000b1'$$,
  '23514',
  null,
  '12: a direct UPDATE cannot bypass the shape rule');

-- ── 6. anon has no way in ────────────────────────────────────────
select ok(
  not has_function_privilege(
    'anon', 'public.set_order_customer_email(uuid, text)', 'execute'),
  '13: anon cannot execute the write path');

select * from finish();
rollback;
