-- ══════════════════════════════════════════════════════════════════
-- pgTAP: manual GCash v2 (platform account → proof attempts → seller
--        verification → admin reconciliation → daily payout)
--
-- Covers the migrations:
--   20261118020000_add_platform_payment_account.sql
--   20261118030000_manual_gcash_flow_v2.sql
--   20261118040000_manual_gcash_rpcs_v2.sql
--   20261118050000_add_seller_payouts.sql
--
-- Run with: supabase test db  (or psql -f against a scratch database).
-- Everything happens inside one transaction and is rolled back.
--
-- Fixtures are inserted explicitly (profiles included). The deployed
-- project creates profiles from an auth.users trigger, but the repo's
-- migration chain does not, so relying on that trigger would make this
-- test pass only on one particular database.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(29);

-- ── identity helper ───────────────────────────────────────────────
create or replace function pg_temp.claims(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (as postgres: RLS bypassed) ──────────────────────────
-- Creating a profile writes a seller_application_audit_log row whose
-- actor_id is auth.uid(); without a claim the fixture insert is rejected.
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-000000000001','authenticated','authenticated','mg-customer@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-000000000002','authenticated','authenticated','mg-seller1@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-000000000003','authenticated','authenticated','mg-seller2@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-0000000000fa','authenticated','authenticated','mg-admin@test.local',    now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('c0000000-0000-0000-0000-000000000001','MG Customer','mg-customer@test.local','customer'),
  ('c0000000-0000-0000-0000-000000000002','MG Seller One','mg-seller1@test.local','seller'),
  ('c0000000-0000-0000-0000-000000000003','MG Seller Two','mg-seller2@test.local','seller'),
  ('c0000000-0000-0000-0000-0000000000fa','MG Admin','mg-admin@test.local','admin')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

-- stores.location is NOT NULL on this schema.
insert into public.stores (id, owner_id, name, location)
values
  ('c0000000-0000-0000-0000-0000000000a1','c0000000-0000-0000-0000-000000000002','MG Store One','Test City'),
  ('c0000000-0000-0000-0000-0000000000a2','c0000000-0000-0000-0000-000000000003','MG Store Two','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('c0000000-0000-0000-0000-0000000000b1','c0000000-0000-0000-0000-0000000000a1',
   'c0000000-0000-0000-0000-000000000002','MG Shoe One', 1000, true),
  ('c0000000-0000-0000-0000-0000000000b2','c0000000-0000-0000-0000-0000000000a2',
   'c0000000-0000-0000-0000-000000000003','MG Shoe Two', 900, true);

insert into public.inventory (product_id, size, stock)
values
  ('c0000000-0000-0000-0000-0000000000b1','40', 10),
  ('c0000000-0000-0000-0000-0000000000b2','40', 10);

-- Deterministic payout maths for the assertions below.
update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100
 where id = 1;

-- Typed scratch table: every checkout result is read through a scalar
-- subquery, which is valid anywhere an expression is allowed.
create temp table _t (
  k        text primary key,
  order_id uuid,
  total    numeric,
  code     text,
  number   text
);

-- ── 1–5. schema ───────────────────────────────────────────────────
select has_column('public','orders','payment_account_id',
  '1: orders stamp the platform account the customer paid');
select has_column('public','orders','order_code',
  '2: orders carry the customer-facing order code');
select has_column('public','gcash_payment_proofs','screenshot_hash',
  '3: proofs carry the screenshot hash');
select has_column('public','gcash_payment_proofs','attempt_no',
  '4: proofs carry the attempt number');
select has_index('public','gcash_payment_proofs','uq_gcash_payment_proofs_screenshot_hash',
  '5: one screenshot cannot back two orders (unique index)');

-- ── 6. no active account → checkout refused ───────────────────────
select pg_temp.claims('c0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$ select public.create_gcash_checkout(
       '[{"product_id":"c0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
       'Test address', null) $$,
  'P0001',
  'Online GCash is being set up. Please use cash on pickup for now.',
  '6: without an active platform account there is no checkout at all'
);

-- ── 7. admin activates the account ────────────────────────────────
insert into public.platform_payment_accounts
  (label, gcash_number, account_name, is_active)
values ('Platform GCash', '09171234567', 'CUFMAI Store', true);

select ok(
  (select is_active from public.platform_payment_accounts where gcash_number = '09171234567'),
  '7: admin activated one platform account'
);

-- ── 8–10. checkout ────────────────────────────────────────────────
insert into _t (k, order_id, total, code, number)
select 'o1',
       (j ->> 'order_id')::uuid,
       (j ->> 'total_amount')::numeric,
       j ->> 'order_code',
       j ->> 'gcash_number'
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"c0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Test address', null) as j
  ) s;

select is(
  (select total from _t where k = 'o1'),
  1100.00,
  '8: total = price + the configured ₱100 delivery'
);
select is(
  (select number from _t where k = 'o1'),
  '09171234567',
  '9: customer is shown the platform account, not a seller number'
);
select isnt(
  (select code from _t where k = 'o1'),
  null,
  '10: checkout returns the order code for the GCash note'
);

-- ── 11. cross-store cart refused (the payout-attribution bug) ─────
-- Cancel order 1 first so the one-open-order cap is not what trips.
select public.cancel_my_pending_gcash_checkout(
  (select order_id from _t where k = 'o1')
);

select throws_ok(
  $$ select public.create_gcash_checkout(
       '[{"product_id":"c0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1},
         {"product_id":"c0000000-0000-0000-0000-0000000000b2","size":"40","quantity":1}]'::jsonb,
       'Test address', null) $$,
  'P0001',
  'Your cart has items from more than one store. Please check out one store at a time.',
  '11: a cart spanning two stores is refused instead of billing the first store'
);

-- ── 12–14. the full happy path order ─────────────────────────────
insert into _t (k, order_id, total, code, number)
select 'o2',
       (j ->> 'order_id')::uuid,
       (j ->> 'total_amount')::numeric,
       j ->> 'order_code',
       j ->> 'gcash_number'
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"c0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Test address', null) as j
  ) s;

-- Wrong amount is rejected before anything is recorded.
select throws_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '1234567890123', 'Juan Cruz', 1000.00,
    %L, repeat('a', 64), now()) $$,
    (select order_id from _t where k = 'o2'),
    (select order_id from _t where k = 'o2')::text || '/shot.jpg'),
  'P0001',
  null,
  '12: an amount that does not match the order total is refused'
);

select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '1234567890123', 'Juan Cruz', 1100.00,
    %L, repeat('a', 64), now()) $$,
    (select order_id from _t where k = 'o2'),
    (select order_id from _t where k = 'o2')::text || '/shot.jpg'),
  '13: a correct proof is accepted'
);

select is(
  (select status from public.orders
    where id = (select order_id from _t where k = 'o2')),
  'payment_under_review',
  '14: a submitted proof moves the order to review (no timer can cancel it)'
);

-- ── 15–17. reject → resubmit (attempts) ──────────────────────────
select pg_temp.claims('c0000000-0000-0000-0000-000000000002');

select is(
  (public.reject_gcash_proof(
     (select order_id from _t where k = 'o2'),
     'Reference not found in GCash') ->> 'status'),
  'awaiting_payment_confirmation',
  '15: a first rejection returns the order to the customer, it does not cancel'
);

select pg_temp.claims('c0000000-0000-0000-0000-000000000001');
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '1234567890124', 'Juan Cruz', 1100.00,
    %L, repeat('b', 64), now()) $$,
    (select order_id from _t where k = 'o2'),
    (select order_id from _t where k = 'o2')::text || '/shot2.jpg'),
  '16: the customer may resubmit after a rejection'
);

select is(
  (select attempt_no from public.gcash_payment_proofs
    where order_id = (select order_id from _t where k = 'o2')
      and status = 'pending'),
  2,
  '17: the resubmission is recorded as attempt 2'
);

-- ── 18–20. seller verification ───────────────────────────────────
select pg_temp.claims('c0000000-0000-0000-0000-000000000002');
select lives_ok(
  format($$ select public.verify_gcash_payment(%L::uuid) $$,
    (select order_id from _t where k = 'o2')),
  '18: the store owner verifies the payment'
);

select is(
  (select status from public.orders
    where id = (select order_id from _t where k = 'o2')),
  'pending',
  '19: verified payment enters the normal fulfilment pipeline'
);

select isnt(
  (select seller_verified_at from public.orders
    where id = (select order_id from _t where k = 'o2')),
  null,
  '20: the seller verification is stamped'
);

-- ── 21–22. admin reconciliation ──────────────────────────────────
select pg_temp.claims('c0000000-0000-0000-0000-000000000002');
select throws_ok(
  format($$ select public.admin_reconcile_order(%L::uuid) $$,
    (select order_id from _t where k = 'o2')),
  'P0001',
  'Only admins can reconcile payments',
  '21: a seller cannot confirm the money landed'
);

select pg_temp.claims('c0000000-0000-0000-0000-0000000000fa');
select lives_ok(
  format($$ select public.admin_reconcile_order(%L::uuid) $$,
    (select order_id from _t where k = 'o2')),
  '22: an admin reconciles the order against the platform statement'
);

-- ── 23–25. payout generation is correct and idempotent ───────────
select public.generate_daily_payouts((now() at time zone 'Asia/Manila')::date);

select is(
  (select net_amount from public.seller_payouts
    where store_id = 'c0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  1000.00,
  '23: payout net = total − ₱100 delivery − 0% commission'
);

select is(
  (select count(*)::int from public.seller_payout_items
    where order_id = (select order_id from _t where k = 'o2')),
  1,
  '24: the order appears exactly once in the payout'
);

select is(
  (public.generate_daily_payouts((now() at time zone 'Asia/Manila')::date)
     ->> 'orders_added')::int,
  0,
  '25: re-running the generator adds nothing (idempotent)'
);

-- ── 26–28. flagging blocks acceptance; payouts refuse non-admins ──
select pg_temp.claims('c0000000-0000-0000-0000-000000000001');
insert into _t (k, order_id, total, code, number)
select 'o3',
       (j ->> 'order_id')::uuid,
       (j ->> 'total_amount')::numeric,
       j ->> 'order_code',
       j ->> 'gcash_number'
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"c0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Test address', null) as j
  ) s;

select pg_temp.claims('c0000000-0000-0000-0000-000000000001');
select public.submit_gcash_proof(
  (select order_id from _t where k = 'o3'),
  '1234567890125', 'Juan Cruz', 1100.00,
  (select order_id from _t where k = 'o3')::text || '/shot3.jpg',
  repeat('c', 64), now());

select pg_temp.claims('c0000000-0000-0000-0000-0000000000fa');
select lives_ok(
  format($$ select public.admin_flag_payment(%L::uuid, 'Not found in statement') $$,
    (select order_id from _t where k = 'o3')),
  '26: an admin can flag a suspicious payment'
);

select pg_temp.claims('c0000000-0000-0000-0000-000000000002');
select throws_ok(
  format($$ select public.verify_gcash_payment(%L::uuid) $$,
    (select order_id from _t where k = 'o3')),
  'P0001',
  'This payment is flagged by an admin. It must be cleared before you can accept it.',
  '27: a flagged payment cannot be accepted by the seller'
);

select throws_ok(
  format($$ select public.mark_payout_paid(%L, 'REF123', null) $$,
    (select id from public.seller_payouts
      where store_id = 'c0000000-0000-0000-0000-0000000000a1')),
  'P0001',
  'Only admins can mark a payout paid',
  '28: a seller cannot mark their own payout paid'
);

-- ── 29. stock really is held, and really is returned ───────────
-- Product b1 starts at 10. Order 1 was cancelled (stock back), orders 2
-- and 3 are live: 10 − 2 = 8. If the reservation trigger never fired this
-- reads 10; if a cancellation did not release, it reads 7.
select is(
  (select stock from public.inventory
    where product_id = 'c0000000-0000-0000-0000-0000000000b1'
      and size = '40'),
  8,
  '29: live checkouts hold stock and the cancelled one gave it back'
);

select * from finish();
rollback;
